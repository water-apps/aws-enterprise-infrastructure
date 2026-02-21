# Monitoring Module - CloudWatch Dashboards & Alarms

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

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name              = "${var.environment}-waterapps-alerts"
  display_name      = "WaterApps Alerts - ${var.environment}"
  kms_master_key_id = var.kms_key_arn

  tags = {
    Name        = "${var.environment}-alerts"
    Environment = var.environment
  }
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.environment}-waterapps-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # ALB Metrics
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", { stat = "Sum", label = "Requests" }],
            [".", "TargetResponseTime", { stat = "Average", label = "Response Time" }],
            [".", "HTTPCode_Target_4XX_Count", { stat = "Sum", label = "4XX Errors" }],
            [".", "HTTPCode_Target_5XX_Count", { stat = "Sum", label = "5XX Errors" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Application Load Balancer"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      # ECS Metrics
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", { stat = "Average", label = "CPU %" }],
            [".", "MemoryUtilization", { stat = "Average", label = "Memory %" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "ECS Service Utilization"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      # RDS Metrics
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", { stat = "Average", label = "CPU %" }],
            [".", "DatabaseConnections", { stat = "Average", label = "Connections" }],
            [".", "FreeableMemory", { stat = "Average", label = "Free Memory" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "RDS Database"
        }
      },
      # CloudFront Metrics
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/CloudFront", "Requests", { stat = "Sum", label = "Requests" }],
            [".", "BytesDownloaded", { stat = "Sum", label = "Bytes Downloaded" }],
            [".", "4xxErrorRate", { stat = "Average", label = "4xx Rate" }],
            [".", "5xxErrorRate", { stat = "Average", label = "5xx Rate" }]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1" # CloudFront metrics are in us-east-1
          title  = "CloudFront Distribution"
        }
      }
    ]
  })
}

# CloudWatch Alarms

# ALB Target Health
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets" {
  alarm_name          = "${var.environment}-alb-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Alert when ALB has unhealthy targets"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  tags = {
    Name        = "${var.environment}-alb-unhealthy-alarm"
    Environment = var.environment
  }
}

# ALB 5XX Errors
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "${var.environment}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Alert when ALB has too many 5xx errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = {
    Name        = "${var.environment}-alb-5xx-alarm"
    Environment = var.environment
  }
}

# ECS CPU Utilization
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${var.environment}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alert when ECS CPU is high"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  tags = {
    Name        = "${var.environment}-ecs-cpu-alarm"
    Environment = var.environment
  }
}

# ECS Memory Utilization
resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name          = "${var.environment}-ecs-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "Alert when ECS memory is high"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  tags = {
    Name        = "${var.environment}-ecs-memory-alarm"
    Environment = var.environment
  }
}

# CloudWatch Log Metric Filter for Application Errors
resource "aws_cloudwatch_log_metric_filter" "application_errors" {
  name           = "${var.environment}-application-errors"
  log_group_name = var.ecs_log_group_name
  pattern        = "[time, request_id, level = ERROR*, ...]"

  metric_transformation {
    name      = "ApplicationErrors"
    namespace = "WaterApps/${var.environment}"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "application_errors" {
  alarm_name          = "${var.environment}-application-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApplicationErrors"
  namespace           = "WaterApps/${var.environment}"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Alert when application has too many errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = {
    Name        = "${var.environment}-app-errors-alarm"
    Environment = var.environment
  }
}

# CloudFront Error Rate
resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx_rate" {
  count = var.cloudfront_distribution_id != null ? 1 : 0

  alarm_name          = "${var.environment}-cloudfront-5xx-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 5
  alarm_description   = "Alert when CloudFront has high 5xx error rate"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DistributionId = var.cloudfront_distribution_id
  }

  tags = {
    Name        = "${var.environment}-cloudfront-5xx-alarm"
    Environment = var.environment
  }
}

# Cost Anomaly Detection
resource "aws_ce_anomaly_monitor" "service" {
  name              = "${var.environment}-waterapps-cost-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"

  tags = {
    Name        = "${var.environment}-cost-monitor"
    Environment = var.environment
  }
}

resource "aws_ce_anomaly_subscription" "cost_alerts" {
  name      = "${var.environment}-cost-anomaly-alerts"
  frequency = "DAILY"

  monitor_arn_list = [
    aws_ce_anomaly_monitor.service.arn
  ]

  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = ["100"] # Alert if anomaly cost > $100
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }

  tags = {
    Name        = "${var.environment}-cost-anomaly-sub"
    Environment = var.environment
  }
}

# Outputs
output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}
