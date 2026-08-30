variable "name" {
  description = "Name prefix applied to all VPC resources (usually '<project>-<env>')."
  type        = string
}

variable "cidr_block" {
  description = "IPv4 CIDR block for the VPC, e.g. 10.0.0.0/16."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR."
  }
}

variable "availability_zones" {
  description = "Availability Zones to spread subnets across. Minimum 2 for high availability."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 Availability Zones are required for a highly available architecture."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets (ALB + NAT Gateway). One per AZ."
  type        = list(string)
}

variable "private_app_subnet_cidrs" {
  description = "CIDRs for the private application tier (ECS tasks). One per AZ."
  type        = list(string)
}

variable "private_data_subnet_cidrs" {
  description = "CIDRs for the private data tier (RDS). One per AZ."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "If true, deploy ONE NAT Gateway shared by all AZs (cheaper, single point of failure). If false, one per AZ (HA, ~3x cost). Use true for dev, false for prod."
  type        = bool
  default     = true
}

variable "enable_interface_endpoints" {
  description = "Create interface VPC endpoints (ECR, Secrets Manager, Logs, STS). Each costs ~$7/month/AZ but removes NAT data-processing charges for AWS API traffic."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch. Recommended for production; adds ingestion cost."
  type        = bool
  default     = false
}

variable "flow_logs_retention_days" {
  description = "CloudWatch retention in days for VPC Flow Logs."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
