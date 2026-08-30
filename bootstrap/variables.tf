variable "aws_region" {
  description = "AWS region for the bootstrap resources (state bucket + KMS key)."
  type        = string
  default     = "eu-west-3"
}

variable "state_bucket_prefix" {
  description = "Prefix for the globally-unique Terraform state bucket name."
  type        = string
  default     = "alios-terraform-state"
}

variable "github_repository" {
  # MUST be set to your real repository. The OIDC trust policy restricts role
  # assumption to this exact string via the `sub` claim condition. A wrong
  # value means GitHub Actions cannot authenticate to AWS at all.
  description = "GitHub repo allowed to assume the CI role, as 'owner/repo'."
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository)) && !startswith(var.github_repository, "aliiios")
    error_message = "Set github_repository to your real 'owner/repo' (e.g. in terraform.tfvars or with -var)."
  }
}

variable "create_github_oidc" {
  description = "Create the GitHub Actions OIDC provider and CI role. Set false if an OIDC provider already exists in the account."
  type        = bool
  default     = true
}
