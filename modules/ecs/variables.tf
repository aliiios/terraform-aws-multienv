variable "name" {
  description = "Name prefix for ECS/ALB resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC to deploy into."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the internet-facing ALB. Must span >= 2 AZs."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private application subnet IDs where Fargate tasks run."
  type        = list(string)
}

variable "container_image" {
  description = "Full image reference, e.g. <account>.dkr.ecr.<region>.amazonaws.com/app:v1.0.0. Prefer an immutable tag or digest."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU). Valid: 256,512,1024,2048,4096."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB. Valid combinations are constrained by task_cpu."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks to run steady-state."
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Autoscaling floor."
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Autoscaling ceiling. Also acts as a cost guardrail."
  type        = number
  default     = 6
}

variable "cpu_target_value" {
  description = "Target average CPU utilisation percentage for target-tracking autoscaling."
  type        = number
  default     = 60
}

variable "enable_autoscaling" {
  description = "Enable Application Auto Scaling for the ECS service."
  type        = bool
  default     = true
}

variable "health_check_path" {
  description = "HTTP path the ALB target group probes."
  type        = string
  default     = "/health"
}

variable "health_check_matcher" {
  description = "HTTP status codes considered healthy."
  type        = string
  default     = "200"
}

variable "deregistration_delay" {
  description = "Seconds the ALB waits for in-flight requests to finish before removing a target (connection draining)."
  type        = number
  default     = 30
}

variable "deployment_minimum_healthy_percent" {
  description = "Lower bound of running tasks during a deployment, as a percent of desired_count."
  type        = number
  default     = 100
}

variable "deployment_maximum_percent" {
  description = "Upper bound of running tasks during a deployment. 200 allows a full parallel replacement set."
  type        = number
  default     = 200
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights (per-task CPU/memory/network metrics). Adds CloudWatch cost."
  type        = bool
  default     = true
}

variable "enable_alb_access_logs" {
  description = "Write ALB access logs to a dedicated S3 bucket."
  type        = bool
  default     = false
}

variable "access_logs_retention_days" {
  description = "Days to retain ALB access logs in S3 before expiry."
  type        = number
  default     = 90
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for container logs. Never leave this at 'never expire' — logs are billed per GB stored."
  type        = number
  default     = 30
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN holding DB credentials. Injected into the container as secrets, never as plaintext env vars."
  type        = string
  default     = null
}

variable "environment_variables" {
  description = "Non-sensitive environment variables for the container."
  type        = map(string)
  default     = {}
}

variable "enable_deletion_protection" {
  description = "Prevent the ALB from being deleted via API/console. True in production."
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM certificate ARN. When set, an HTTPS:443 listener is created and HTTP:80 redirects to it."
  type        = string
  default     = null
}

variable "enable_execute_command" {
  description = "Allow `aws ecs execute-command` (ECS Exec) for debugging into running tasks."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
