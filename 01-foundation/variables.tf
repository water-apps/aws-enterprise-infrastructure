variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-southeast-2"  # Sydney region
}

variable "dev_account_email" {
  description = "Email for development account root user"
  type        = string
  # Example: dev+waterapps@yourdomain.com
}

variable "prod_account_email" {
  description = "Email for production account root user"
  type        = string
  # Example: prod+waterapps@yourdomain.com
}

variable "shared_account_email" {
  description = "Email for shared services account root user"
  type        = string
  # Example: shared+waterapps@yourdomain.com
}

variable "budget_alert_email" {
  description = "Email address for budget alerts"
  type        = string
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  type        = string
  default     = "300"
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "WaterApps"
    ManagedBy   = "Terraform"
    Owner       = "VK"
    Company     = "WaterApps"
    CostCenter  = "Engineering"
  }
}
