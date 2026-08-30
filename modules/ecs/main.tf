# =============================================================================
# ECS MODULE — Fargate service behind an Application Load Balancer
#
# TRAFFIC PATH:
#   Internet -> ALB (public subnets) -> Target Group -> Fargate task ENI
#               (private app subnets, no public IP)
#
# SECURITY GROUP CHAIN (referenced, never CIDR-based between tiers):
#   ALB SG : allows 80/443 from 0.0.0.0/0
#   ECS SG : allows container_port ONLY from the ALB SG
#   RDS SG : allows 5432 ONLY from the ECS SG   (rule added by the caller)
#
# Referencing a security GROUP instead of a CIDR means the rule follows the
# workload automatically: scale the ALB, replace tasks, change subnets — the
# rule stays correct because identity, not IP address, is what is authorised.
# =============================================================================

locals {
  common_tags = merge(var.tags, { Module = "ecs" })
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "main" {}

# -----------------------------------------------------------------------------
# CLUSTER
# A cluster is a logical grouping/namespace. With Fargate it provisions
# nothing itself — there are no EC2 instances to manage. That is the whole
# point of Fargate: AWS owns the host, patching, and capacity.
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(local.common_tags, { Name = "${var.name}-cluster" })
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  # FARGATE_SPOT is up to ~70% cheaper but tasks can be reclaimed with a
  # 2-minute warning. Suitable for stateless, fault-tolerant workloads.
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# -----------------------------------------------------------------------------
# LOGGING
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# =============================================================================
# IAM ROLES — the distinction interviewers ask about
#
# TASK EXECUTION ROLE
#   Used by the ECS AGENT (the AWS-managed infrastructure), BEFORE and
#   AROUND your container. It pulls the image from ECR, fetches secrets from
#   Secrets Manager to inject them, and writes container logs to CloudWatch.
#   Your application code NEVER uses this role.
#
# TASK ROLE
#   Assumed by YOUR APPLICATION CODE at runtime, via the container credential
#   endpoint. This is the role your SDK calls (S3, DynamoDB, SQS...) use.
#
# Two roles exist so the platform's permissions and the application's
# permissions are separated: your app can read from S3 without being able to
# pull arbitrary images or read every secret in the account.
# =============================================================================

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.name}-task-execution"
  description        = "Used by the ECS agent to pull images, fetch secrets and write logs"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = local.common_tags
}

# The AWS-managed baseline: ECR pull + CloudWatch Logs write.
resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Secrets access, scoped to THIS service's secret ARN only — not secretsmanager:*.
data "aws_iam_policy_document" "task_execution_secrets" {
  count = var.db_secret_arn != null ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  count = var.db_secret_arn != null ? 1 : 0

  name   = "read-db-secret"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_secrets[0].json
}

resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  description        = "Assumed by the application code running in the container"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = local.common_tags
}

# ECS Exec needs SSM messaging permissions on the TASK role (not execution).
data "aws_iam_policy_document" "task_exec_command" {
  count = var.enable_execute_command ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_exec_command" {
  count = var.enable_execute_command ? 1 : 0

  name   = "ecs-exec"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_exec_command[0].json
}

# =============================================================================
# SECURITY GROUPS
# =============================================================================
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "Internet-facing ALB for ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "${var.name}-alb-sg" })

  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count = var.certificate_arn != null ? 1 : 0

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# ALB -> tasks only. Not 0.0.0.0/0.
resource "aws_vpc_security_group_egress_rule" "alb_to_tasks" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward traffic to ECS tasks"
  referenced_security_group_id = aws_security_group.ecs_tasks.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.name}-ecs-tasks-sg"
  description = "Fargate tasks for ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "${var.name}-ecs-tasks-sg" })

  lifecycle { create_before_destroy = true }
}

# THE KEY RULE: only the ALB security group may reach the container port.
# There is no CIDR here at all — nothing else in the VPC can reach the tasks.
resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs_tasks.id
  description                  = "Application traffic from the ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

# Tasks need outbound HTTPS: ECR image pulls, Secrets Manager, CloudWatch.
# With VPC endpoints in place most of this never leaves the VPC.
resource "aws_vpc_security_group_egress_rule" "ecs_https" {
  security_group_id = aws_security_group.ecs_tasks.id
  description       = "HTTPS to AWS APIs and the internet via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# Egress to the database. The matching INGRESS rule on the RDS security group
# is created by the caller to avoid a circular module dependency.
resource "aws_vpc_security_group_egress_rule" "ecs_to_db" {
  count = var.db_secret_arn != null ? 1 : 0

  security_group_id = aws_security_group.ecs_tasks.id
  description       = "PostgreSQL to the data tier"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

# =============================================================================
# APPLICATION LOAD BALANCER
#
# ALB (Layer 7) vs NLB (Layer 4):
#   ALB understands HTTP: it can route on host/path/header, terminate TLS,
#   and run HTTP health checks. NLB is faster and preserves the client IP at
#   the TCP level but cannot make HTTP-aware decisions.
#   We need path/host routing and HTTP health checks -> ALB.
# =============================================================================
resource "aws_lb" "this" {
  name               = substr("${var.name}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  # Protects against desynchronisation-based request smuggling attacks.
  desync_mitigation_mode     = "defensive"
  drop_invalid_header_fields = true

  idle_timeout = 60

  dynamic "access_logs" {
    for_each = var.enable_alb_access_logs ? [1] : []
    content {
      bucket  = aws_s3_bucket.alb_logs[0].id
      prefix  = var.name
      enabled = true
    }
  }

  tags = merge(local.common_tags, { Name = "${var.name}-alb" })
}

# -----------------------------------------------------------------------------
# TARGET GROUP
# target_type = "ip" is MANDATORY for Fargate: with awsvpc networking each
# task gets its own ENI and private IP, so targets are registered by IP,
# not by instance ID.
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "this" {
  name        = substr("${var.name}-tg", 0, 32)
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  # CONNECTION DRAINING: on deregistration the ALB stops sending NEW requests
  # but lets in-flight ones finish for this many seconds. Too low = truncated
  # requests during deploys; too high = slow deployments.
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = var.health_check_matcher
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2 # consecutive successes before receiving traffic
    unhealthy_threshold = 3 # consecutive failures before removal
  }

  # The target group is referenced by the ECS service; replacing it requires
  # creating the new one first.
  lifecycle { create_before_destroy = true }

  tags = merge(local.common_tags, { Name = "${var.name}-tg" })
}

# HTTP listener. Without a certificate it serves traffic directly (dev only);
# with one it permanently redirects to HTTPS.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.certificate_arn == null ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.this.arn
    }
  }

  dynamic "default_action" {
    for_each = var.certificate_arn != null ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count = var.certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  # TLS 1.2 minimum; TLS 1.0/1.1 are deprecated and fail most audits.
  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# -----------------------------------------------------------------------------
# ALB ACCESS LOGS BUCKET
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "alb_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket        = "${var.name}-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = merge(local.common_tags, { Name = "${var.name}-alb-logs" })
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket                  = aws_s3_bucket.alb_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      # ALB access logs only support SSE-S3 (AES256), not SSE-KMS.
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = var.access_logs_retention_days
    }
  }
}

# In older regions (including eu-west-3) the ALB writes logs using a
# per-region AWS-owned account, so the bucket policy grants that principal.
data "aws_iam_policy_document" "alb_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
    resources = ["${aws_s3_bucket.alb_logs[0].arn}/${var.name}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
  }

  statement {
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.alb_logs[0].arn}/${var.name}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    effect  = "Allow"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    resources = [aws_s3_bucket.alb_logs[0].arn]
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id
  policy = data.aws_iam_policy_document.alb_logs[0].json
}

# =============================================================================
# TASK DEFINITION
#
# A task definition is an immutable, versioned blueprint. Every change creates
# a NEW REVISION; it never mutates in place. The service points at a revision,
# which is what makes rollback a matter of pointing back at the old one.
# =============================================================================
resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]

  # awsvpc is the ONLY networking mode Fargate supports: each task receives
  # its own ENI with a private IP, so tasks get real security groups rather
  # than sharing a host's network stack.
  network_mode = "awsvpc"

  cpu    = var.task_cpu
  memory = var.task_memory

  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn      = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = var.name
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        },
      ]

      # NON-SENSITIVE values only. Anything here is visible in plaintext to
      # anyone with ecs:DescribeTaskDefinition.
      environment = [
        for k, v in var.environment_variables : { name = k, value = v }
      ]

      # SENSITIVE values. ECS resolves these at task START time using the
      # TASK EXECUTION ROLE and injects them into the container environment.
      # The value never appears in the task definition, in state, or in logs.
      secrets = var.db_secret_arn != null ? [
        { name = "DB_USERNAME", valueFrom = "${var.db_secret_arn}:username::" },
        { name = "DB_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" },
        { name = "DB_HOST", valueFrom = "${var.db_secret_arn}:host::" },
        { name = "DB_PORT", valueFrom = "${var.db_secret_arn}:port::" },
        { name = "DB_NAME", valueFrom = "${var.db_secret_arn}:dbname::" },
      ] : []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      # Container-level health check, evaluated by the ECS agent. This is
      # SEPARATE from the ALB health check: ECS restarts an unhealthy
      # container, the ALB stops routing to an unhealthy target.
      healthCheck = {
        command     = ["CMD-SHELL", "wget -q --spider http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      readonlyRootFilesystem = false
    },
  ])

  tags = merge(local.common_tags, { Name = "${var.name}-task" })
}

# =============================================================================
# ECS SERVICE
#
# The service is the controller that keeps `desired_count` tasks running,
# replaces failed tasks, registers/deregisters them with the target group,
# and orchestrates rolling deployments.
# =============================================================================
resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # ROLLING DEPLOYMENT MECHANICS
  #   min 100 / max 200 means: start the new tasks FIRST (up to 2x desired),
  #   wait for them to pass ALB health checks, register them, then drain and
  #   stop the old ones. Capacity never drops below 100% -> zero downtime.
  #   If the new tasks fail health checks they are never registered, the old
  #   tasks keep serving, and the circuit breaker rolls the deployment back.
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  deployment_circuit_breaker {
    enable   = true
    rollback = true # automatically revert to the last healthy revision
  }

  enable_execute_command = var.enable_execute_command

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false # tasks are private; egress goes via NAT/endpoints
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.name
    container_port   = var.container_port
  }

  # Give tasks time to boot before the service starts counting health check
  # failures against them.
  health_check_grace_period_seconds = 60

  # Spreads tasks across AZs first, then across instances — maximising
  # survival of an AZ failure.
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  lifecycle {
    # Autoscaling owns desired_count at runtime. Without this, every
    # `terraform apply` would reset the service back to the static value
    # and undo whatever autoscaling had decided.
    ignore_changes = [desired_count]
  }

  # The listener must exist before the service can register targets.
  depends_on = [aws_lb_listener.http]

  tags = merge(local.common_tags, { Name = "${var.name}-service" })
}

# =============================================================================
# APPLICATION AUTO SCALING
#
# TARGET TRACKING: you declare a target metric value and AWS computes the
# required capacity, like a thermostat. Simpler and more robust than step
# scaling for the common CPU/memory case.
#
# Scale-out is deliberately faster than scale-in: being slow to add capacity
# hurts users, being slow to remove it only costs a little money.
# =============================================================================
resource "aws_appautoscaling_target" "this" {
  count = var.enable_autoscaling ? 1 : 0

  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.enable_autoscaling ? 1 : 0

  name               = "${var.name}-cpu-target-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_target_value
    scale_in_cooldown  = 300 # slow to remove capacity
    scale_out_cooldown = 60  # fast to add it
  }
}

resource "aws_appautoscaling_policy" "memory" {
  count = var.enable_autoscaling ? 1 : 0

  name               = "${var.name}-memory-target-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 75
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# =============================================================================
# CLOUDWATCH ALARMS
# =============================================================================
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.name}-unhealthy-targets"
  alarm_description   = "One or more targets are failing ALB health checks"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 0
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.this.arn_suffix
    LoadBalancer = aws_lb.this.arn_suffix
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  alarm_name          = "${var.name}-alb-5xx"
  alarm_description   = "Elevated 5xx responses from the target group"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 10
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.this.arn_suffix
    LoadBalancer = aws_lb.this.arn_suffix
  }

  tags = local.common_tags
}
