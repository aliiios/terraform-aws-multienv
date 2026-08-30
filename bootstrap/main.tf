# =============================================================================
# BOOTSTRAP
#
# Creates the shared foundations that cannot be created by the environment
# configurations themselves:
#   1. The S3 bucket used as the Terraform remote-state backend.
#   2. The KMS key that encrypts it.
#   3. The GitHub Actions OIDC provider + IAM role (so CI needs no AWS keys).
#
# Run ONCE, with local state. See README.md in this directory.
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# -----------------------------------------------------------------------------
# Unique suffix
#
# S3 bucket names are globally unique across ALL AWS accounts, not just yours.
# random_id generates a suffix once and then persists it in state, so repeated
# plans/applies keep the SAME bucket name (it is not re-randomised).
# -----------------------------------------------------------------------------
resource "random_id" "suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# KMS key for state encryption
#
# WHY a customer-managed key instead of the default S3-managed key (SSE-S3)?
#   - Key usage is logged in CloudTrail -> auditable "who read the state".
#   - We control rotation policy explicitly.
#   - Key access can be revoked independently of bucket permissions.
# Cost: ~$1/month for the key itself.
# -----------------------------------------------------------------------------
resource "aws_kms_key" "state" {
  description             = "Encrypts the Terraform remote state bucket"
  deletion_window_in_days = 30 # safety window; key deletion is irreversible
  enable_key_rotation     = true

  tags = { Name = "terraform-state-key" }
}

resource "aws_kms_alias" "state" {
  name          = "alias/terraform-state-key"
  target_key_id = aws_kms_key.state.key_id
}

# -----------------------------------------------------------------------------
# The state bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket = "${var.state_bucket_prefix}-${random_id.suffix.hex}"

  # GUARDRAIL: this bucket holds the state for the entire project.
  # `terraform destroy` or any replace-forcing change will fail at PLAN time
  # rather than silently destroying it.
  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = "terraform-remote-state" }
}

# Versioning: every state write creates a new object version, so a corrupted
# or accidentally-overwritten state can be rolled back from the S3 console.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    # COST OPTIMISATION: without this, every S3 GET/PUT on a KMS-encrypted
    # object makes a billed KMS API call. bucket_key_enabled caches a
    # bucket-level data key, cutting KMS request volume dramatically.
    bucket_key_enabled = true
  }
}

# Four independent switches. Even if a future bucket policy or ACL mistake
# tried to expose this bucket, these override it.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Old state versions accumulate. Expire them after 90 days to control cost
# while keeping a meaningful recovery window.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket     = aws_s3_bucket.state.id
  depends_on = [aws_s3_bucket_versioning.state]

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {} # applies to all objects

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Enforce TLS. An explicit Deny always beats any Allow in IAM evaluation,
# so this blocks plain-HTTP access even for otherwise-authorised callers.
resource "aws_s3_bucket_policy" "state_tls_only" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.state.arn,
          "${aws_s3_bucket.state.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })
}

# =============================================================================
# GITHUB ACTIONS OIDC
#
# WHY: so CI never stores long-lived AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY.
#
# HOW IT WORKS:
#   1. A workflow requests a signed JWT from GitHub's OIDC issuer.
#   2. The workflow calls sts:AssumeRoleWithWebIdentity with that JWT.
#   3. AWS validates the JWT signature against the OIDC provider below.
#   4. AWS checks the trust policy conditions (audience + subject claim).
#   5. AWS returns SHORT-LIVED credentials.
# Nothing long-lived is ever stored in GitHub.
# =============================================================================
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # AWS now validates GitHub's certificate chain against trusted root CAs,
  # so this thumbprint is no longer security-critical, but the argument
  # remains required by the API.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = { Name = "github-actions-oidc" }
}

data "aws_iam_policy_document" "github_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    # The audience claim must be sts.amazonaws.com.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # CRITICAL: the subject claim restricts WHICH repo/branch can assume this
    # role. Without this condition ANY GitHub repo on the internet could
    # assume it. This is the single most important line in the trust policy.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:ref:refs/heads/main",
        "repo:${var.github_repository}:pull_request",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  count = var.create_github_oidc ? 1 : 0

  name               = "github-actions-terraform"
  description        = "Assumed by GitHub Actions via OIDC to run Terraform"
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json
  max_session_duration = 3600

  tags = { Name = "github-actions-terraform" }
}

# NOTE ON LEAST PRIVILEGE:
# PowerUserAccess is broad. It is used here so the pipeline can manage every
# service in this project without hand-maintaining a 200-line policy. It does
# NOT include IAM write access, which is granted separately and narrowly below.
# In a real production account you would replace this with a policy scoped to
# the exact actions and resource ARNs your modules touch (see docs/SECURITY.md).
resource "aws_iam_role_policy_attachment" "github_actions_poweruser" {
  count = var.create_github_oidc ? 1 : 0

  role       = aws_iam_role.github_actions[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/PowerUserAccess"
}

# PowerUserAccess deliberately excludes IAM. Terraform must create the ECS
# task role / task execution role, so we add exactly those actions.
data "aws_iam_policy_document" "github_actions_iam" {
  statement {
    sid    = "IAMForTerraform"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:PassRole",
      "iam:TagRole",
      "iam:ListRoleTags",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:CreateServiceLinkedRole",
    ]
    resources = ["*"]
  }

  # Access to the state bucket + its KMS key.
  statement {
    sid    = "TerraformState"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
  }

  statement {
    sid    = "StateKMS"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.state.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_iam" {
  count = var.create_github_oidc ? 1 : 0

  name   = "terraform-iam-and-state"
  role   = aws_iam_role.github_actions[0].id
  policy = data.aws_iam_policy_document.github_actions_iam.json
}
