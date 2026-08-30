# -----------------------------------------------------------------------------
# All environment differences are expressed through .tfvars values, NOT through
# conditional logic in the code. Same code path everywhere -> what you test in
# dev is structurally identical to what runs in prod.
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name used as a prefix for all resource names."
  type        = string
  default     = "tf-aws-multienv"
}

variable "environment" {
  description = "Environment name."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for this environment."
  type        = string
}

variable "availability_zones" {
  description = "Availability Zones to deploy across. Minimum 2."
  type        = list(string)
}

# --- Networking ---
variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must not overlap other environments."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDRs for the public subnets."
  type        = list(string)
}

variable "private_app_subnet_cidrs" {
  description = "CIDRs for the private application subnets."
  type        = list(string)
}

variable "private_data_subnet_cidrs" {
  description = "CIDRs for the private data subnets."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "One shared NAT Gateway (cheap) vs one per AZ (highly available)."
  type        = bool
}

variable "enable_interface_endpoints" {
  description = "Create interface VPC endpoints for AWS APIs."
  type        = bool
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs."
  type        = bool
  default     = false
}

# --- Database ---
variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "db_allocated_storage" {
  description = "RDS storage in GiB."
  type        = number
}

variable "db_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.4"
}

variable "db_multi_az" {
  description = "Deploy an RDS standby in a second AZ."
  type        = bool
}

variable "db_backup_retention_period" {
  description = "Days of automated RDS backups."
  type        = number
}

variable "db_deletion_protection" {
  description = "Block RDS deletion via API/console."
  type        = bool
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot when destroying the database."
  type        = bool
}

variable "db_monitoring_interval" {
  description = "RDS Enhanced Monitoring interval in seconds (0 = off)."
  type        = number
  default     = 0
}

variable "db_performance_insights_enabled" {
  description = "Enable RDS Performance Insights."
  type        = bool
  default     = false
}

# --- Application / ECS ---
variable "container_image" {
  description = "Container image reference. Use an immutable tag or digest."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080
}

variable "task_cpu" {
  description = "Fargate task CPU units."
  type        = number
}

variable "task_memory" {
  description = "Fargate task memory in MiB."
  type        = number
}

variable "desired_count" {
  description = "Steady-state task count."
  type        = number
}

variable "min_capacity" {
  description = "Autoscaling minimum tasks."
  type        = number
}

variable "max_capacity" {
  description = "Autoscaling maximum tasks."
  type        = number
}

variable "enable_autoscaling" {
  description = "Enable ECS service autoscaling."
  type        = bool
  default     = true
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights."
  type        = bool
  default     = true
}

variable "enable_alb_access_logs" {
  description = "Write ALB access logs to S3."
  type        = bool
  default     = false
}

variable "enable_alb_deletion_protection" {
  description = "Prevent ALB deletion."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for container logs."
  type        = number
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS. Null serves plain HTTP (dev only)."
  type        = string
  default     = null
}

variable "enable_execute_command" {
  description = "Allow ECS Exec for interactive debugging."
  type        = bool
  default     = false
}
