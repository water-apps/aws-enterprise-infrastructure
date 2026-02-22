variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

variable "environment" {
  description = "Environment name (development, production)"
  type        = string
}

variable "database_subnet_ids" {
  description = "List of subnet IDs for database"
  type        = list(string)
}

variable "rds_security_group_id" {
  description = "Security group ID for RDS"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "waterapps"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "waterapps_admin"
}

variable "db_master_password" {
  description = "Database master password (from Secrets Manager)"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro" # Free tier eligible / cost-optimized for dev
  # Production: db.t4g.small, db.r6g.large, etc.
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.1"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Maximum allocated storage for autoscaling in GB"
  type        = number
  default     = 100
}

variable "max_db_connections" {
  description = "Maximum number of database connections"
  type        = string
  default     = "100"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["ap-southeast-2a", "ap-southeast-2b"]
}

variable "enable_read_replica" {
  description = "Enable read replica (production only)"
  type        = bool
  default     = false
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms"
  type        = string
  default     = null
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project   = "WaterApps"
    ManagedBy = "Terraform"
  }
}
