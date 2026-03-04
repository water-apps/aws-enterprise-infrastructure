variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

variable "environment" {
  description = "Environment name (development, production)"
  type        = string
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project   = "WaterApps"
    ManagedBy = "Terraform"
  }
}

variable "enable_legacy_cicd_iam_user" {
  description = "Temporary escape hatch to create long-lived CI/CD IAM user access keys. Keep false and use OIDC-based CI/CD instead."
  type        = bool
  default     = false
}
