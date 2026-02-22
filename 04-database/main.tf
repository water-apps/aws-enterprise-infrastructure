# Database Module - RDS PostgreSQL

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.common_tags
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-db-subnet-group"
  subnet_ids = var.database_subnet_ids

  tags = {
    Name        = "${var.environment}-db-subnet-group"
    Environment = var.environment
  }
}

# DB Parameter Group for PostgreSQL optimization
resource "aws_db_parameter_group" "postgres" {
  name   = "${var.environment}-postgres-params"
  family = "postgres16"

  # Optimize for application workload
  parameter {
    name         = "shared_buffers"
    value        = "{DBInstanceClassMemory/32768}" # 25% of RAM
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "effective_cache_size"
    value        = "{DBInstanceClassMemory/16384}" # 75% of RAM
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "maintenance_work_mem"
    value        = "2097152" # 2GB
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "checkpoint_completion_target"
    value        = "0.9"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "wal_buffers"
    value        = "16384" # 16MB
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "default_statistics_target"
    value        = "100"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "random_page_cost"
    value        = "1.1" # Optimized for SSD
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "effective_io_concurrency"
    value        = "200"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "work_mem"
    value        = "10485" # 10MB per operation
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "max_connections"
    value        = var.max_db_connections
    apply_method = "pending-reboot"
  }

  tags = {
    Name        = "${var.environment}-postgres-params"
    Environment = var.environment
  }
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier = "${var.environment}-waterapps-db"

  # Engine
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  # Storage
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn
  iops                  = var.environment == "production" ? 3000 : null
  storage_throughput    = var.environment == "production" ? 125 : null

  # Database
  db_name  = var.db_name
  username = var.db_username
  password = var.db_master_password
  port     = 5432

  # High Availability
  multi_az          = var.environment == "production" ? true : false
  availability_zone = var.environment == "production" ? null : var.availability_zones[0]

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]
  publicly_accessible    = false

  # Backup
  backup_retention_period   = var.environment == "production" ? 30 : 7
  backup_window             = "03:00-04:00" # Sydney time: 1-2 PM
  maintenance_window        = "Mon:04:00-Mon:05:00"
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.environment == "development"
  final_snapshot_identifier = var.environment == "production" ? "${var.environment}-waterapps-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null
  delete_automated_backups  = var.environment == "development"

  # Performance Insights
  performance_insights_enabled          = var.environment == "production"
  performance_insights_retention_period = var.environment == "production" ? 7 : null
  performance_insights_kms_key_id       = var.environment == "production" ? var.kms_key_arn : null

  # Enhanced Monitoring
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  monitoring_interval             = var.environment == "production" ? 60 : 0
  monitoring_role_arn             = var.environment == "production" ? aws_iam_role.rds_monitoring[0].arn : null

  # Parameters
  parameter_group_name = aws_db_parameter_group.postgres.name

  # Options
  auto_minor_version_upgrade = true
  deletion_protection        = var.environment == "production"

  # Apply changes immediately in dev, during maintenance window in prod
  apply_immediately = var.environment == "development"

  tags = {
    Name        = "${var.environment}-waterapps-db"
    Environment = var.environment
  }

  lifecycle {
    ignore_changes = [
      password # Prevent recreation when password rotates
    ]
  }
}

# IAM Role for Enhanced Monitoring (production only)
resource "aws_iam_role" "rds_monitoring" {
  count = var.environment == "production" ? 1 : 0
  name  = "${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-rds-monitoring-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count      = var.environment == "production" ? 1 : 0
  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Read Replica for production (optional - enable when needed)
resource "aws_db_instance" "read_replica" {
  count = var.enable_read_replica && var.environment == "production" ? 1 : 0

  identifier = "${var.environment}-waterapps-db-replica"

  replicate_source_db = aws_db_instance.main.identifier
  instance_class      = var.db_instance_class

  # Can be in different AZ for better distribution
  availability_zone = var.availability_zones[1]

  # Storage
  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  # Network
  publicly_accessible = false

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  performance_insights_kms_key_id       = var.kms_key_arn

  # Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring[0].arn

  auto_minor_version_upgrade = true
  skip_final_snapshot        = true

  tags = {
    Name        = "${var.environment}-waterapps-db-replica"
    Environment = var.environment
    Type        = "read-replica"
  }
}

# CloudWatch alarms for database monitoring
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${var.environment}-db-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.environment == "production" ? 80 : 90
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = {
    Name        = "${var.environment}-db-cpu-alarm"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "database_storage" {
  alarm_name          = "${var.environment}-db-storage-space"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 10737418240 # 10 GB
  alarm_description   = "This metric monitors RDS free storage space"
  alarm_actions       = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = {
    Name        = "${var.environment}-db-storage-alarm"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  alarm_name          = "${var.environment}-db-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.max_db_connections * 0.8 # 80% of max connections
  alarm_description   = "This metric monitors RDS database connections"
  alarm_actions       = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = {
    Name        = "${var.environment}-db-connections-alarm"
    Environment = var.environment
  }
}

# Outputs
output "db_instance_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
}

output "db_instance_address" {
  description = "RDS instance address"
  value       = aws_db_instance.main.address
}

output "db_instance_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "db_instance_name" {
  description = "RDS instance database name"
  value       = aws_db_instance.main.db_name
}

output "db_instance_username" {
  description = "RDS instance master username"
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "db_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.main.id
}

output "read_replica_endpoint" {
  description = "RDS read replica endpoint"
  value       = var.enable_read_replica && var.environment == "production" ? aws_db_instance.read_replica[0].endpoint : null
}
