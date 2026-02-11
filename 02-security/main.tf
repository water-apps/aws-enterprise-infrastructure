# Security Module - KMS, Secrets Manager, IAM Roles

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

# KMS Key for encryption at rest
resource "aws_kms_key" "main" {
  description             = "${var.environment} encryption key"
  deletion_window_in_days = var.environment == "production" ? 30 : 7
  enable_key_rotation     = true

  tags = {
    Name        = "${var.environment}-kms-key"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.environment}-waterapps"
  target_key_id = aws_kms_key.main.key_id
}

# Secrets Manager for database credentials
resource "aws_secretsmanager_secret" "db_master_password" {
  name                    = "${var.environment}/waterapps/db/master-password"
  description             = "Master password for RDS database"
  recovery_window_in_days = var.environment == "production" ? 30 : 7
  kms_key_id              = aws_kms_key.main.arn

  tags = {
    Name        = "${var.environment}-db-master-password"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "db_master_password" {
  secret_id     = aws_secretsmanager_secret.db_master_password.id
  secret_string = random_password.db_master_password.result
}

resource "random_password" "db_master_password" {
  length  = 32
  special = true
  # Avoid characters that might cause issues in connection strings
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Secrets for application configuration
resource "aws_secretsmanager_secret" "app_config" {
  name                    = "${var.environment}/waterapps/app/config"
  description             = "Application configuration secrets"
  recovery_window_in_days = var.environment == "production" ? 30 : 7
  kms_key_id              = aws_kms_key.main.arn

  tags = {
    Name        = "${var.environment}-app-config"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "app_config" {
  secret_id = aws_secretsmanager_secret.app_config.id
  secret_string = jsonencode({
    jwt_secret     = random_password.jwt_secret.result
    api_key        = random_password.api_key.result
    encryption_key = random_password.encryption_key.result
  })
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "random_password" "api_key" {
  length  = 32
  special = false
}

resource "random_password" "encryption_key" {
  length  = 32
  special = false
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.environment}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-ecs-task-execution-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Custom policy for ECS to access secrets
resource "aws_iam_role_policy" "ecs_secrets_access" {
  name = "${var.environment}-ecs-secrets-access"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.db_master_password.arn,
          aws_secretsmanager_secret.app_config.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.main.arn
      }
    ]
  })
}

# IAM Role for ECS Tasks (application runtime)
resource "aws_iam_role" "ecs_task" {
  name = "${var.environment}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-ecs-task-role"
    Environment = var.environment
  }
}

# Policy for ECS tasks to access S3 (for file uploads, etc.)
resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${var.environment}-ecs-task-s3"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.environment}-waterapps-*",
          "arn:aws:s3:::${var.environment}-waterapps-*/*"
        ]
      }
    ]
  })
}

# IAM Role for CI/CD (GitHub Actions)
resource "aws_iam_user" "cicd" {
  name = "${var.environment}-cicd-user"

  tags = {
    Name        = "${var.environment}-cicd-user"
    Environment = var.environment
    Purpose     = "CI/CD deployments"
  }
}

resource "aws_iam_access_key" "cicd" {
  user = aws_iam_user.cicd.name
}

resource "aws_iam_user_policy" "cicd" {
  name = "${var.environment}-cicd-policy"
  user = aws_iam_user.cicd.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.ecs_task_execution.arn,
          aws_iam_role.ecs_task.arn
        ]
      }
    ]
  })
}

# Store CI/CD credentials in Secrets Manager
resource "aws_secretsmanager_secret" "cicd_credentials" {
  name                    = "${var.environment}/waterapps/cicd/credentials"
  description             = "CI/CD IAM user credentials"
  recovery_window_in_days = 7

  tags = {
    Name        = "${var.environment}-cicd-credentials"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "cicd_credentials" {
  secret_id = aws_secretsmanager_secret.cicd_credentials.id
  secret_string = jsonencode({
    access_key_id     = aws_iam_access_key.cicd.id
    secret_access_key = aws_iam_access_key.cicd.secret
  })
}

# Outputs
output "kms_key_id" {
  description = "KMS key ID"
  value       = aws_kms_key.main.key_id
}

output "kms_key_arn" {
  description = "KMS key ARN"
  value       = aws_kms_key.main.arn
}

output "db_master_password_secret_arn" {
  description = "ARN of database master password secret"
  value       = aws_secretsmanager_secret.db_master_password.arn
}

output "app_config_secret_arn" {
  description = "ARN of application config secret"
  value       = aws_secretsmanager_secret.app_config.arn
}

output "ecs_task_execution_role_arn" {
  description = "ARN of ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "ARN of ECS task role"
  value       = aws_iam_role.ecs_task.arn
}

output "cicd_user_name" {
  description = "CI/CD IAM user name"
  value       = aws_iam_user.cicd.name
}

output "cicd_credentials_secret_arn" {
  description = "ARN of CI/CD credentials secret"
  value       = aws_secretsmanager_secret.cicd_credentials.arn
  sensitive   = true
}
