# =============================================================================
# Native `terraform test` suite for the VPC module.
# Run from modules/vpc with:  terraform test
#
# `command = plan` means these are PLAN-TIME assertions: nothing is created,
# nothing costs money, and the suite runs in seconds. This is the right level
# for structural/configuration invariants. Use Terratest only when you must
# assert on RUNTIME behaviour (can A actually reach B over the network).
# =============================================================================

variables {
  name                      = "test-vpc"
  cidr_block                = "10.99.0.0/16"
  availability_zones        = ["eu-west-3a", "eu-west-3b"]
  public_subnet_cidrs       = ["10.99.0.0/24", "10.99.1.0/24"]
  private_app_subnet_cidrs  = ["10.99.10.0/24", "10.99.11.0/24"]
  private_data_subnet_cidrs = ["10.99.20.0/24", "10.99.21.0/24"]
}

run "creates_correct_subnet_counts" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Expected 2 public subnets, one per AZ."
  }

  assert {
    condition     = length(aws_subnet.private_app) == 2
    error_message = "Expected 2 private application subnets."
  }

  assert {
    condition     = length(aws_subnet.private_data) == 2
    error_message = "Expected 2 private data subnets."
  }
}

run "subnets_span_multiple_azs" {
  command = plan

  assert {
    condition     = length(distinct(aws_subnet.private_app[*].availability_zone)) >= 2
    error_message = "Application subnets must span at least 2 AZs for high availability."
  }
}

run "app_and_data_subnets_are_not_public" {
  command = plan

  assert {
    condition     = alltrue([for s in aws_subnet.private_app : s.map_public_ip_on_launch == false])
    error_message = "Application subnets must not auto-assign public IPs."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private_data : s.map_public_ip_on_launch == false])
    error_message = "Data subnets must not auto-assign public IPs."
  }
}

run "dns_is_enabled_for_private_endpoints" {
  command = plan

  assert {
    condition     = aws_vpc.this.enable_dns_support && aws_vpc.this.enable_dns_hostnames
    error_message = "DNS support and hostnames are required for interface VPC endpoint private DNS."
  }
}

run "gateway_endpoints_exist" {
  command = plan

  assert {
    condition     = aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway"
    error_message = "The S3 endpoint must be a Gateway endpoint (free, route-table based)."
  }

  assert {
    condition     = aws_vpc_endpoint.dynamodb.vpc_endpoint_type == "Gateway"
    error_message = "The DynamoDB endpoint must be a Gateway endpoint."
  }
}

run "interface_endpoints_use_private_dns" {
  command = plan

  assert {
    condition     = alltrue([for e in aws_vpc_endpoint.interface : e.private_dns_enabled])
    error_message = "Interface endpoints must enable private DNS, otherwise traffic still leaves via NAT."
  }
}

run "endpoint_security_group_is_not_open_to_the_world" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.vpc_endpoints_https[0].cidr_ipv4 != "0.0.0.0/0"
    error_message = "VPC endpoint security group must not accept traffic from the entire internet."
  }
}

run "rejects_single_availability_zone" {
  command = plan

  variables {
    availability_zones        = ["eu-west-3a"]
    public_subnet_cidrs       = ["10.99.0.0/24"]
    private_app_subnet_cidrs  = ["10.99.10.0/24"]
    private_data_subnet_cidrs = ["10.99.20.0/24"]
  }

  expect_failures = [var.availability_zones]
}
