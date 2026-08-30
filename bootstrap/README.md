# Bootstrap

Creates the foundations that the environment configurations cannot create for
themselves:

- The S3 bucket used as the Terraform remote-state backend
- The customer-managed KMS key that encrypts it
- The GitHub Actions OIDC provider and CI IAM role

## Why this uses local state, permanently

`terraform init` resolves the backend **before** any resource exists. This
configuration creates the bucket that every other configuration uses as its
backend — so if it used that bucket as its own backend, `init` would fail
because the bucket does not exist yet.

That is the chicken-and-egg problem, and local state is the standard solution.
`bootstrap/` is the single intentional exception in this repository.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# EDIT terraform.tfvars: github_repository must be your real owner/repo.
# The OIDC trust policy restricts role assumption to that exact string.

terraform init
terraform plan -out=bootstrap.tfplan
terraform apply bootstrap.tfplan

terraform output state_bucket_name        # -> environments/*/backend.tf
terraform output github_actions_role_arn  # -> GitHub repo variable AWS_ROLE_ARN
```

Run this once. After it succeeds you should not need to touch this directory
again.

## Protect the local state file

`bootstrap/terraform.tfstate` lives on your machine and is gitignored. It is
the only state file with no remote backup — by design, since it cannot use the
bucket it creates. Back it up:

```bash
cp bootstrap/terraform.tfstate ~/backups/bootstrap-$(date +%F).tfstate
```

If you lose it, the resources still exist in AWS but Terraform no longer knows
about them. Recovery means importing them back:

```bash
terraform import aws_kms_key.state <key-id>
terraform import aws_kms_alias.state alias/terraform-state-key
terraform import aws_s3_bucket.state <bucket-name>
```

## Verification

```bash
BUCKET=$(terraform output -raw state_bucket_name)
aws s3api get-bucket-versioning     --bucket $BUCKET
aws s3api get-bucket-encryption     --bucket $BUCKET
aws s3api get-public-access-block   --bucket $BUCKET
aws s3api get-bucket-policy         --bucket $BUCKET --query Policy --output text | jq .
```

Expect: versioning `Enabled`, encryption `aws:kms`, all four public-access
booleans `true`, and a policy denying insecure transport.
