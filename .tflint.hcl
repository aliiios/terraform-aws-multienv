# tflint configuration.
# Run locally with: tflint --recursive
# Also enforced in CI (.github/workflows/terraform-ci.yml) and pre-commit.

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.30.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Enforce a consistent naming convention for variables/outputs/resources.
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# Every variable and output must be documented. This is what makes
# terraform-docs output useful instead of a wall of empty descriptions.
rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

# Require explicit types on variables (catches accidental "any").
rule "terraform_typed_variables" {
  enabled = true
}

# Require provider version constraints — no implicit "latest".
rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}
