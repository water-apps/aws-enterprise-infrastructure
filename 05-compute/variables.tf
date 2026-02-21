variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

variable "environment" {
  description = "Environment name (development, production)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
}

variable "ecs_task_execution_role_arn" {
  description = "ECS task execution role ARN"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "ECS task role ARN"
  type        = string
}

variable "db_instance_address" {
  description = "RDS instance address"
  type        = string
}

variable "db_instance_port" {
  description = "RDS instance port"
  type        = number
}

variable "db_instance_name" {
  description = "Database name"
  type        = string
}

variable "db_master_password_secret_arn" {
  description = "ARN of database password secret"
  type        = string
}

variable "app_config_secret_arn" {
  description = "ARN of application config secret"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS (optional for initial setup)"
  type        = string
  default     = null
}

variable "task_cpu" {
  description = "ECS task CPU units"
  type        = string
  default     = "256" # 0.25 vCPU
  # Options: 256, 512, 1024, 2048, 4096
}

variable "task_memory" {
  description = "ECS task memory in MB"
  type        = string
  default     = "512" # 512 MB
  # Options depend on CPU: 256 CPU → 512-2048 MB
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 1
}

variable "min_capacity" {
  description = "Minimum number of ECS tasks"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of ECS tasks"
  type        = number
  default     = 4
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project   = "WaterApps"
    ManagedBy = "Terraform"
  }
}
