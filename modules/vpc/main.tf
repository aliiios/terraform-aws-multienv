# =============================================================================
# VPC MODULE — three-tier network
#
#   Public tier        : ALB + NAT Gateway. Route to Internet Gateway.
#   Private app tier   : ECS Fargate tasks. Route to NAT (egress only).
#   Private data tier  : RDS. NO route to NAT and NO route to IGW —
#                        completely isolated from the internet in BOTH
#                        directions. This is the strongest possible network
#                        posture for a database and is a key talking point.
#
# WHY three tiers instead of two?
#   A two-tier design (public/private) puts the database in the same subnets
#   as the application, which means the DB inherits a NAT route it does not
#   need. Removing that route eliminates an entire class of data-exfiltration
#   path: a compromised database cannot call out to the internet at all.
# =============================================================================

locals {
  az_count = length(var.availability_zones)

  common_tags = merge(var.tags, {
    Module = "vpc"
  })

  # If single_nat_gateway is true we create 1 NAT; otherwise one per AZ.
  nat_gateway_count = var.single_nat_gateway ? 1 : local.az_count

  # Interface endpoints to create. Each becomes an ENI in every private app
  # subnet, with a private DNS name that shadows the public AWS API endpoint.
  interface_endpoints = var.enable_interface_endpoints ? {
    ecr_api         = "com.amazonaws.${data.aws_region.current.region}.ecr.api"
    ecr_dkr         = "com.amazonaws.${data.aws_region.current.region}.ecr.dkr"
    secretsmanager  = "com.amazonaws.${data.aws_region.current.region}.secretsmanager"
    logs            = "com.amazonaws.${data.aws_region.current.region}.logs"
    sts             = "com.amazonaws.${data.aws_region.current.region}.sts"
    ssm             = "com.amazonaws.${data.aws_region.current.region}.ssm"
    ssmmessages     = "com.amazonaws.${data.aws_region.current.region}.ssmmessages"
  } : {}
}

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block = var.cidr_block

  # BOTH are required for interface VPC endpoints to work via private DNS.
  # enable_dns_support   -> the Amazon-provided DNS resolver at VPC base +2
  # enable_dns_hostnames -> instances/ENIs get DNS hostnames
  # Without these, `secretsmanager.eu-west-3.amazonaws.com` would still
  # resolve to the PUBLIC IP and your traffic would leave via NAT.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = var.name })
}

# -----------------------------------------------------------------------------
# Internet Gateway — the VPC's door to the internet.
# An IGW is horizontally scaled, redundant and highly available by design;
# it is not a bandwidth bottleneck and it costs nothing.
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.name}-igw" })
}

# -----------------------------------------------------------------------------
# SUBNETS
#
# A subnet lives in exactly ONE Availability Zone and cannot span AZs — that
# is why we create one subnet per tier per AZ. An AZ is a distinct set of
# datacentres with independent power/cooling/networking, so spreading across
# AZs is what makes the architecture survive a datacentre failure.
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # ALB nodes need public IPs; this is the only tier where this is true.
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "private_app" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # Explicitly false: Fargate tasks must never receive a public IP.
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.name}-private-app-${var.availability_zones[count.index]}"
    Tier = "private-app"
  })
}

resource "aws_subnet" "private_data" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_data_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.name}-private-data-${var.availability_zones[count.index]}"
    Tier = "private-data"
  })
}

# -----------------------------------------------------------------------------
# NAT GATEWAY
#
# Allows the private app tier to make OUTBOUND connections (pull images from
# public registries, call third-party APIs) while remaining unreachable from
# the internet. It is a managed, AZ-scoped service.
#
# COST WARNING: NAT Gateway is one of the most expensive components in this
# whole architecture — roughly $32/month per gateway PLUS a per-GB data
# processing charge. This is exactly why single_nat_gateway defaults to true
# in dev and why we add VPC endpoints for AWS API traffic.
# -----------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = merge(local.common_tags, { Name = "${var.name}-nat-eip-${count.index}" })
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  # The NAT Gateway itself lives in a PUBLIC subnet — it needs an IGW route
  # to reach the internet on behalf of the private subnets.
  subnet_id = aws_subnet.public[count.index].id

  # Implicit dependency on the IGW exists via routing, but AWS requires the
  # IGW to be attached before the NAT is usable, so make it explicit.
  depends_on = [aws_internet_gateway.this]

  tags = merge(local.common_tags, { Name = "${var.name}-nat-${count.index}" })
}

# -----------------------------------------------------------------------------
# ROUTE TABLES
# -----------------------------------------------------------------------------

# Public: default route to the Internet Gateway. One table shared by all
# public subnets (they all behave identically).
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.name}-rt-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private app: default route to NAT. ONE TABLE PER AZ, because each AZ may
# point at a different NAT Gateway (when single_nat_gateway = false).
# Keeping traffic within its own AZ also avoids cross-AZ data transfer cost.
resource "aws_route_table" "private_app" {
  count = local.az_count

  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags, {
    Name = "${var.name}-rt-private-app-${var.availability_zones[count.index]}"
  })
}

resource "aws_route" "private_app_nat" {
  count = local.az_count

  route_table_id         = aws_route_table.private_app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  # With a single NAT every AZ points at index 0; otherwise at its own AZ's NAT.
  nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private_app" {
  count          = local.az_count
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

# Private data: NO default route at all.
# The table contains only the implicit local route for intra-VPC traffic.
# The database can therefore talk to the app tier and nothing else.
resource "aws_route_table" "private_data" {
  count = local.az_count

  vpc_id = aws_vpc.this.id
  tags = merge(local.common_tags, {
    Name = "${var.name}-rt-private-data-${var.availability_zones[count.index]}"
  })
}

resource "aws_route_table_association" "private_data" {
  count          = local.az_count
  subnet_id      = aws_subnet.private_data[count.index].id
  route_table_id = aws_route_table.private_data[count.index].id
}

# =============================================================================
# VPC ENDPOINTS
#
# TWO DIFFERENT TECHNOLOGIES, often confused:
#
#  GATEWAY endpoints (S3, DynamoDB only)
#    - A ROUTE TABLE ENTRY with a prefix list destination.
#    - No ENI, no private IP, NO HOURLY COST. Free.
#    - Only reachable from inside the VPC.
#
#  INTERFACE endpoints (everything else, powered by AWS PrivateLink)
#    - An actual ENI with a private IP in your subnet.
#    - Private DNS makes the normal AWS service hostname resolve to that ENI.
#    - Costs ~$0.01/hour PER AZ plus per-GB processing.
#
# WHY BOTH MATTER FOR ECR:
#   Pulling a container image is a TWO-STEP operation.
#     1. ECS calls the ECR API (auth token, manifest)  -> ecr.api  (interface)
#     2. ECS downloads the image LAYERS, which are stored in S3 -> S3 (gateway)
#   If you create the ECR interface endpoints but forget the S3 GATEWAY
#   endpoint, image pulls STILL go out through NAT (or fail in a NAT-less
#   subnet). This is one of the most common real-world VPC endpoint mistakes.
# =============================================================================

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"

  # Attach to the app tier route tables so ECS can fetch image layers
  # privately. Data tier deliberately excluded (RDS does not need S3).
  route_table_ids = aws_route_table.private_app[*].id

  tags = merge(local.common_tags, { Name = "${var.name}-vpce-s3" })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private_app[*].id

  tags = merge(local.common_tags, { Name = "${var.name}-vpce-dynamodb" })
}

# Security group for the interface endpoint ENIs.
# Only the VPC CIDR may reach them, and only on 443.
resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_interface_endpoints ? 1 : 0

  name        = "${var.name}-vpce-sg"
  description = "Allows HTTPS from within the VPC to interface VPC endpoints"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${var.name}-vpce-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https" {
  count = var.enable_interface_endpoints ? 1 : 0

  security_group_id = aws_security_group.vpc_endpoints[0].id
  description       = "HTTPS from inside the VPC"
  cidr_ipv4         = aws_vpc.this.cidr_block
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id            = aws_vpc.this.id
  service_name      = each.value
  vpc_endpoint_type = "Interface"

  # One ENI per app subnet -> the endpoint survives an AZ failure.
  subnet_ids         = aws_subnet.private_app[*].id
  security_group_ids = [aws_security_group.vpc_endpoints[0].id]

  # This is what makes it transparent: the standard service hostname now
  # resolves to the endpoint's private IP, so no application code changes.
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${var.name}-vpce-${each.key}" })
}

# =============================================================================
# VPC FLOW LOGS (optional — enable in prod)
# Records accepted/rejected traffic metadata. Essential for security forensics
# and for debugging "why can't A reach B" without packet capture.
# =============================================================================
resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = var.flow_logs_retention_days

  tags = local.common_tags
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name               = "${var.name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name   = "flow-logs-write"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  iam_role_arn         = aws_iam_role.flow_logs[0].arn
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs[0].arn

  tags = merge(local.common_tags, { Name = "${var.name}-flow-logs" })
}
