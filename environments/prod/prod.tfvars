# =============================================================================
# PRODUCTION — availability, durability and observability over cost.
#
# NOT APPLIED in this project (cost control). Validated with `terraform plan`.
#
# Every difference from dev is deliberate:
#   NAT per AZ          -> no single AZ takes down egress
#   Interface endpoints -> AWS API traffic never traverses NAT or the internet
#   Multi-AZ RDS        -> automatic failover to a synchronous standby
#   30-day backups      -> meaningful point-in-time recovery window
#   Deletion protection -> a fat-fingered destroy cannot delete the database
#   Flow logs + Insights-> forensics and capacity data when it matters
# =============================================================================
environment = "prod"
aws_region  = "eu-west-3"

availability_zones        = ["eu-west-3a", "eu-west-3b", "eu-west-3c"]
vpc_cidr                  = "10.2.0.0/16"
public_subnet_cidrs       = ["10.2.0.0/24", "10.2.1.0/24", "10.2.2.0/24"]
private_app_subnet_cidrs  = ["10.2.10.0/24", "10.2.11.0/24", "10.2.12.0/24"]
private_data_subnet_cidrs = ["10.2.20.0/24", "10.2.21.0/24", "10.2.22.0/24"]

single_nat_gateway         = false
enable_interface_endpoints = true
enable_flow_logs           = true

db_instance_class               = "db.m6g.large"
db_allocated_storage            = 100
db_multi_az                     = true
db_backup_retention_period      = 30
db_deletion_protection          = true
db_skip_final_snapshot          = false
db_monitoring_interval          = 30
db_performance_insights_enabled = true

# In production this MUST be an immutable ECR tag or a digest, never `latest`.
container_image = "public.ecr.aws/nginx/nginx:1.27-alpine"
container_port  = 80

task_cpu      = 1024
task_memory   = 2048
desired_count = 3
min_capacity  = 3
max_capacity  = 12

enable_autoscaling             = true
enable_container_insights      = true
enable_alb_access_logs         = true
enable_alb_deletion_protection = true
# ECS Exec gives shell access to running containers — disabled in prod.
enable_execute_command = false
log_retention_days     = 90

# Set this to a real ACM certificate ARN to enable HTTPS + HTTP->HTTPS redirect.
# certificate_arn = "arn:aws:acm:eu-west-3:123456789012:certificate/xxxx"
