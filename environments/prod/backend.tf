terraform {
  # ---------------------------------------------------------------------------
  # PARTIAL BACKEND CONFIGURATION
  #
  # bucket and region are supplied at init time rather than hardcoded:
  #
  #     cp backend.hcl.example backend.hcl   # fill in your bucket
  #     terraform init -backend-config=backend.hcl
  #
  # WHY NOT HARDCODE THEM:
  #   The bucket name is account-specific and globally unique, so hardcoding it
  #   makes the repository non-portable and publishes an internal resource name.
  #
  # WHY NOT USE A VARIABLE:
  #   Backend blocks cannot reference variables. Terraform resolves the backend
  #   BEFORE variables are evaluated, so partial configuration is the supported
  #   mechanism for account-specific values.
  #
  # use_lockfile = true -> S3-NATIVE state locking (Terraform >= 1.11).
  #   Terraform writes a <key>.tflock object into the same bucket for the
  #   duration of an operation. The legacy DynamoDB lock table is not needed.
  # ---------------------------------------------------------------------------
  backend "s3" {
    key          = "prod/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
