# =============================================================================
# STAGING — production-LIKE architecture at reduced capacity.
#
# NOT APPLIED in this project (cost control). Validated with `terraform plan`.
# The point of staging is that its SHAPE matches prod: same Multi-AZ, same
# endpoints, same monitoring — only the sizes differ. A staging environment
# that is architecturally different from prod tests nothing useful.
# =============================================================================
environment = "staging"
aws_region  = "eu-west-3"

availability_zones        = ["eu-west-3a", "eu-west-3b"]
vpc_cidr                  = "10.1.0.0/16"
public_subnet_cidrs       = ["10.1.0.0/24", "10.1.1.0/24"]
private_app_subnet_cidrs  = ["10.1.10.0/24", "10.1.11.0/24"]
private_data_subnet_cidrs = ["10.1.20.0/24", "10.1.21.0/24"]

single_nat_gateway         = false
enable_interface_endpoints = true
enable_flow_logs           = true

db_instance_class               = "db.t4g.small"
db_allocated_storage            = 50
db_multi_az                     = true
db_backup_retention_period      = 7
db_deletion_protection          = true
db_skip_final_snapshot          = false
db_monitoring_interval          = 60
db_performance_insights_enabled = true

container_image = "public.ecr.aws/nginx/nginx:1.27-alpine"
container_port  = 80

task_cpu      = 512
task_memory   = 1024
desired_count = 2
min_capacity  = 2
max_capacity  = 6

enable_autoscaling             = true
enable_container_insights      = true
enable_alb_access_logs         = true
enable_alb_deletion_protection = false
enable_execute_command         = true
log_retention_days             = 30
