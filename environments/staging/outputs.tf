output "application_url" {
  description = "Public URL of the application."
  value       = "http://${module.ecs.alb_dns_name}"
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = module.ecs.alb_dns_name
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Private application subnet IDs."
  value       = module.vpc.private_app_subnet_ids
}

output "private_data_subnet_ids" {
  description = "Private data subnet IDs."
  value       = module.vpc.private_data_subnet_ids
}

output "ecr_repository_url" {
  description = "ECR repository URL to push the application image to."
  value       = module.ecr.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = module.ecs.service_name
}

output "rds_endpoint" {
  description = "RDS connection endpoint (reachable only from the app tier)."
  value       = module.rds.endpoint
}

output "db_secret_name" {
  description = "Secrets Manager secret holding the database credentials."
  value       = module.rds.secret_name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for container logs."
  value       = module.ecs.log_group_name
}
