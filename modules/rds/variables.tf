variable "name" {
  description = "Name prefix for RDS resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC the database is deployed into."
  type        = string
}

variable "subnet_ids" {
  description = "Private DATA-tier subnet IDs for the DB subnet group. Must span >= 2 AZs."
  type        = list(string)
}

variable "engine" {
  description = "Database engine (e.g. postgres, mysql)."
  type        = string
  default     = "postgres"
}

variable "engine_version" {
  description = "Engine version. Pin it — do not rely on the AWS default."
  type        = string
  default     = "16.4"
}

variable "family" {
  description = "DB parameter group family, must match engine_version (e.g. postgres16)."
  type        = string
  default     = "postgres16"
}

variable "instance_class" {
  description = "RDS instance class (e.g. db.t4g.micro for dev, db.m6g.large for prod)."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Upper bound for storage autoscaling in GiB. Set equal to allocated_storage to disable."
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Name of the initial database created on the instance."
  type        = string
  default     = "appdb"
}

variable "username" {
  description = "Master username. The PASSWORD is generated, never supplied."
  type        = string
  default     = "appadmin"
}

variable "port" {
  description = "Database port."
  type        = number
  default     = 5432
}

variable "multi_az" {
  description = "Deploy a synchronous standby in a second AZ. Doubles cost; required for production."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Days of automated backups. 0 DISABLES backups and also disables point-in-time recovery."
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "Daily backup window in UTC (hh:mm-hh:mm)."
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC (ddd:hh:mm-ddd:hh:mm)."
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "deletion_protection" {
  description = "Block deletion of the instance via API/console. Always true in production."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. True is acceptable for dev only."
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring granularity in seconds (0 disables; 1,5,10,15,30,60 valid)."
  type        = number
  default     = 0
}

variable "performance_insights_enabled" {
  description = "Enable RDS Performance Insights (query-level performance analysis)."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for storage encryption. Null uses the AWS-managed RDS key."
  type        = string
  default     = null
}

variable "apply_immediately" {
  description = "Apply modifications immediately instead of during the maintenance window. Use false in production."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags for all resources in this module."
  type        = map(string)
  default     = {}
}
