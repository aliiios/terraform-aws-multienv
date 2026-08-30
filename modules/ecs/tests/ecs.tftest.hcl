# =============================================================================
# Plan-time tests for the ECS module.
# =============================================================================

variables {
  name               = "test-ecs"
  vpc_id             = "vpc-12345678"
  public_subnet_ids  = ["subnet-11111111", "subnet-22222222"]
  private_subnet_ids = ["subnet-33333333", "subnet-44444444"]
  container_image    = "public.ecr.aws/nginx/nginx:1.27-alpine"
  container_port     = 80
}

run "tasks_have_no_public_ip" {
  command = plan

  assert {
    condition     = aws_ecs_service.this.network_configuration[0].assign_public_ip == false
    error_message = "CRITICAL: Fargate tasks must not be assigned public IP addresses."
  }
}

run "tasks_run_in_private_subnets" {
  command = plan

  assert {
    condition     = toset(aws_ecs_service.this.network_configuration[0].subnets) == toset(var.private_subnet_ids)
    error_message = "ECS tasks must run in the private application subnets."
  }
}

run "fargate_requires_awsvpc_networking" {
  command = plan

  assert {
    condition     = aws_ecs_task_definition.this.network_mode == "awsvpc"
    error_message = "Fargate requires awsvpc network mode."
  }
}

run "target_group_uses_ip_targets" {
  command = plan

  assert {
    condition     = aws_lb_target_group.this.target_type == "ip"
    error_message = "Fargate tasks register by IP, so the target group target_type must be 'ip'."
  }
}

run "execution_and_task_roles_are_distinct" {
  command = plan

  assert {
    condition     = aws_iam_role.task_execution.name != aws_iam_role.task.name
    error_message = "The task execution role and the task role must be separate identities."
  }
}

run "deployment_is_zero_downtime" {
  command = plan

  assert {
    condition     = aws_ecs_service.this.deployment_minimum_healthy_percent >= 100
    error_message = "Minimum healthy percent must be >= 100 so capacity never drops during a deployment."
  }

  assert {
    condition     = aws_ecs_service.this.deployment_circuit_breaker[0].rollback == true
    error_message = "The deployment circuit breaker must roll back failed deployments automatically."
  }
}

run "logs_do_not_retain_forever" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.app.retention_in_days > 0
    error_message = "Log retention must be set; unbounded retention grows cost forever."
  }
}

run "alb_drops_invalid_headers" {
  command = plan

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields == true
    error_message = "The ALB must drop invalid HTTP headers to mitigate request smuggling."
  }
}
