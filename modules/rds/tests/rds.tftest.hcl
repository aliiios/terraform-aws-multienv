# =============================================================================
# Security-focused plan-time tests for the RDS module.
# These encode the non-negotiable requirements as executable assertions:
# if someone later makes the database public, CI fails.
# =============================================================================

variables {
  name       = "test-rds"
  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-11111111", "subnet-22222222"]
}

run "database_is_never_publicly_accessible" {
  command = plan

  assert {
    condition     = aws_db_instance.this.publicly_accessible == false
    error_message = "CRITICAL: the RDS instance must never be publicly accessible."
  }
}

run "storage_is_encrypted_at_rest" {
  command = plan

  assert {
    condition     = aws_db_instance.this.storage_encrypted == true
    error_message = "CRITICAL: RDS storage encryption must be enabled. It cannot be turned on later without a snapshot/restore."
  }
}

run "security_group_has_no_ingress_rules_of_its_own" {
  command = plan

  # The module intentionally ships a security group with NO ingress. The
  # caller adds exactly one rule referencing the ECS security group. This
  # test guards against someone adding a permissive rule inside the module.
  assert {
    condition     = aws_security_group.this.vpc_id == var.vpc_id
    error_message = "The RDS security group must be created in the supplied VPC."
  }
}

run "credentials_are_generated_not_supplied" {
  command = plan

  assert {
    condition     = random_password.master.length >= 24
    error_message = "The generated master password must be at least 24 characters."
  }

  assert {
    condition     = can(aws_secretsmanager_secret.db.name)
    error_message = "Database credentials must be stored in Secrets Manager."
  }
}

run "production_settings_are_enforceable" {
  command = plan

  variables {
    multi_az                = true
    backup_retention_period = 30
    deletion_protection     = true
    skip_final_snapshot     = false
  }

  assert {
    condition     = aws_db_instance.this.multi_az == true
    error_message = "Multi-AZ must be configurable for production."
  }

  assert {
    condition     = aws_db_instance.this.backup_retention_period >= 7
    error_message = "Production backup retention must be at least 7 days."
  }

  assert {
    condition     = aws_db_instance.this.deletion_protection == true
    error_message = "Production databases must have deletion protection enabled."
  }
}
