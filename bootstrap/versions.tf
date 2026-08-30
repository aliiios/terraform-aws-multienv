terraform {
  # >= 1.11 is REQUIRED: that is the version that introduced native S3 state
  # locking (`use_lockfile`), which lets us drop the legacy DynamoDB lock table.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # ---------------------------------------------------------------------------
  # NOTE: there is deliberately NO `backend` block here.
  #
  # THE CHICKEN-AND-EGG PROBLEM:
  #   `terraform init` resolves the backend BEFORE any resource exists.
  #   This configuration CREATES the S3 bucket that every other configuration
  #   uses as its backend. If this config used that bucket as its own backend,
  #   init would fail because the bucket does not exist yet.
  #
  # SOLUTION: bootstrap keeps LOCAL state, permanently. It is the single
  # intentional exception in this repository.
  # ---------------------------------------------------------------------------
}

provider "aws" {
  region = var.aws_region

  # default_tags applies these to every taggable resource this provider
  # creates. Tagging discipline drives cost allocation and governance.
  default_tags {
    tags = {
      Project   = "terraform-aws-multienv"
      ManagedBy = "terraform"
      Component = "bootstrap"
    }
  }
}
