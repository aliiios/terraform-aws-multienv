output "state_bucket_name" {
  description = "Name of the S3 state bucket. Copy this into every environments/*/backend.tf."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the Terraform state bucket."
  value       = aws_s3_bucket.state.arn
}

output "state_kms_key_arn" {
  description = "ARN of the KMS key encrypting the state bucket."
  value       = aws_kms_key.state.arn
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions to assume via OIDC. Set as the AWS_ROLE_ARN repository variable."
  value       = try(aws_iam_role.github_actions[0].arn, null)
}

output "account_id" {
  description = "AWS account ID these resources were created in."
  value       = data.aws_caller_identity.current.account_id
}
