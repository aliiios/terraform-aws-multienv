terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # NO `provider "aws" {}` block here.
  # Child modules DECLARE which providers they need; the ROOT module
  # CONFIGURES them and the child inherits that configuration.
  # Putting a provider block in a child module breaks reusability and
  # prevents the caller from passing aliased/multi-region providers.
}
