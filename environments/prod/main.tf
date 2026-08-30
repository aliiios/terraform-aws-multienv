# =============================================================================
# ROOT MODULE
#
# Composes the vpc, ecr, rds and ecs child modules into one environment.
# This file contains almost no logic — composition and wiring only. All
# sizing/behaviour differences between environments come from the .tfvars file.
# =============================================================================

locals {
  name = "${var.project_name}-${var.environment}"
}

# -----------------------------------------------------------------------------
# NETWORK
# -----------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  name                      = local.name
  cidr_block                = var.vpc_cidr
  availability_zones        = var.availability_zones
  public_subnet_cidrs       = var.public_subnet_cidrs
  private_app_subnet_cidrs  = var.private_app_subnet_cidrs
  private_data_subnet_cidrs = var.private_data_subnet_cidrs

  single_nat_gateway         = var.single_nat_gateway
  enable_interface_endpoints = var.enable_interface_endpoints
  enable_flow_logs           = var.enable_flow_logs
}

# -----------------------------------------------------------------------------
# CONTAINER REGISTRY
# -----------------------------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  name = local.name

  # Immutable tags everywhere: a deployed tag can never be silently replaced.
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true

  # Only dev may nuke a non-empty repository.
  force_delete = var.environment == "dev"
}

# -----------------------------------------------------------------------------
# DATABASE (private data tier)
# -----------------------------------------------------------------------------
module "rds" {
  source = "../../modules/rds"

  name       = local.name
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_data_subnet_ids

  engine         = "postgres"
  engine_version = var.db_engine_version
  family         = "postgres${split(".", var.db_engine_version)[0]}"

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage

  multi_az                     = var.db_multi_az
  backup_retention_period      = var.db_backup_retention_period
  deletion_protection          = var.db_deletion_protection
  skip_final_snapshot          = var.db_skip_final_snapshot
  monitoring_interval          = var.db_monitoring_interval
  performance_insights_enabled = var.db_performance_insights_enabled

  # Never apply DB changes immediately in prod — wait for the maintenance window.
  apply_immediately = var.environment != "prod"
}

# -----------------------------------------------------------------------------
# COMPUTE + LOAD BALANCER
# -----------------------------------------------------------------------------
module "ecs" {
  source = "../../modules/ecs"

  name               = local.name
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_app_subnet_ids

  container_image = var.container_image
  container_port  = var.container_port
  task_cpu        = var.task_cpu
  task_memory     = var.task_memory

  desired_count      = var.desired_count
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
  enable_autoscaling = var.enable_autoscaling

  # Credentials are injected from Secrets Manager at task start — never as
  # plaintext environment variables.
  db_secret_arn = module.rds.secret_arn

  environment_variables = {
    ENVIRONMENT = var.environment
    AWS_REGION  = var.aws_region
  }

  enable_container_insights  = var.enable_container_insights
  enable_alb_access_logs     = var.enable_alb_access_logs
  enable_deletion_protection = var.enable_alb_deletion_protection
  log_retention_days         = var.log_retention_days
  certificate_arn            = var.certificate_arn
  enable_execute_command     = var.enable_execute_command
}

# =============================================================================
# CROSS-MODULE SECURITY GROUP RULE
#
# This rule lives HERE, not inside the rds module, to break a circular
# dependency:
#     rds would need the ECS security group id  (rds -> ecs)
#     ecs needs the Secrets Manager ARN from rds (ecs -> rds)
# Terraform cannot resolve a cycle between modules, so the cross-cutting rule
# is declared in the root module that already depends on both.
#
# Note it references a SECURITY GROUP, not a CIDR: only workloads carrying the
# ECS task security group may reach the database, regardless of their IP.
# =============================================================================
resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  security_group_id            = module.rds.security_group_id
  description                  = "PostgreSQL from the ECS task security group only"
  referenced_security_group_id = module.ecs.ecs_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}
