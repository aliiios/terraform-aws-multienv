# =============================================================================
# DEV — optimised for LOW COST.
# This is the only environment that is actually applied to AWS in this project.
# =============================================================================
environment = "dev"
aws_region  = "eu-west-3"

availability_zones        = ["eu-west-3a", "eu-west-3b"]
vpc_cidr                  = "10.0.0.0/16"
public_subnet_cidrs       = ["10.0.0.0/24", "10.0.1.0/24"]
private_app_subnet_cidrs  = ["10.0.10.0/24", "10.0.11.0/24"]
private_data_subnet_cidrs = ["10.0.20.0/24", "10.0.21.0/24"]

# ONE NAT Gateway shared by both AZs. Saves ~$32/month at the cost of an
# AZ-level single point of failure — an acceptable trade-off in dev.
single_nat_gateway = true

# Interface endpoints cost ~$7/month each per AZ. In dev the NAT already
# exists, so they are disabled; the S3/DynamoDB GATEWAY endpoints are free
# and always created.
enable_interface_endpoints = false
enable_flow_logs           = false

# --- Database: smallest supported instance, minimal backups ---
db_instance_class               = "db.t4g.micro"
db_allocated_storage            = 20
db_multi_az                     = false
db_backup_retention_period      = 1
db_deletion_protection          = false
db_skip_final_snapshot          = true
db_monitoring_interval          = 0
db_performance_insights_enabled = false

# --- Application ---
# Start with a public image so the stack comes up before you have pushed
# anything. Replace with the ECR URL + immutable tag after your first push:
#   <account>.dkr.ecr.eu-west-3.amazonaws.com/tf-aws-multienv-dev:v1.0.0
container_image = "public.ecr.aws/nginx/nginx:1.27-alpine"
container_port  = 80

task_cpu      = 256
task_memory   = 512
desired_count = 1
min_capacity  = 1
max_capacity  = 3

enable_autoscaling             = true
enable_container_insights      = false
enable_alb_access_logs         = false
enable_alb_deletion_protection = false
enable_execute_command         = true
log_retention_days             = 7
