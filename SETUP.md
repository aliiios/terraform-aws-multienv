# Setup — from clone to running

Follow in order. Steps 1–3 are one-time.

## 0. Prerequisites

```bash
terraform version     # must be >= 1.11
aws --version         # must be 2.x
aws sts get-caller-identity   # must return a NON-root ARN
```

## 1. Push this repository to GitHub

### 1a. Validate first — this gates everything else

```bash
make validate-all
terraform fmt -recursive -check
```

Both must pass. Pushing code that fails `terraform validate` is the fastest way
to damage the credibility of a portfolio repository.

### 1b. Build the git history

Commit in phases — one commit per component — rather than a single opaque
"initial commit". See the repository's commit history for the pattern used.

### 1c. Create the repository and push

```bash
gh repo create terraform-aws-multienv --public --source=. --remote=origin --push
```

Or manually:

```bash
git remote add origin git@github.com:<your-user>/terraform-aws-multienv.git
git push -u origin main
```

Then on github.com set the repository **description** and **topics**:
`terraform`, `aws`, `ecs-fargate`, `devops`, `infrastructure-as-code`, `ci-cd`,
`terraform-modules`.

## 2. Bootstrap the state backend

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# EDIT terraform.tfvars: set github_repository to your real owner/repo

terraform init
terraform apply

terraform output state_bucket_name
terraform output github_actions_role_arn
```

Back up the local state file — it is the only one without a remote copy:

```bash
mkdir -p ~/backups && cp terraform.tfstate ~/backups/bootstrap.tfstate
```

## 3. Wire the backend into the environments

The backends use **partial configuration**: the bucket name is account-specific
and is supplied at init time rather than committed.

```bash
cd ..
BUCKET=$(cd bootstrap && terraform output -raw state_bucket_name)

for ENV in dev staging prod; do
  sed "s/REPLACE-WITH-YOUR-STATE-BUCKET/$BUCKET/" \
    environments/$ENV/backend.hcl.example > environments/$ENV/backend.hcl
done
```

`backend.hcl` is gitignored. The committed `backend.hcl.example` documents the
required keys so anyone cloning the repo knows what to supply.

From now on, initialise each environment with:

```bash
terraform init -backend-config=backend.hcl
```

## 4. Configure GitHub

Repository → **Settings**:

| Where | Name | Value |
|---|---|---|
| Secrets and variables → Actions → **Variables** | `AWS_ROLE_ARN` | the `github_actions_role_arn` output |
| Secrets and variables → Actions → **Secrets** | `INFRACOST_API_KEY` | free key from infracost.io |
| **Environments** | `dev`, `staging`, `prod` | add required reviewers on staging and prod |
| **Branches** | protect `main` | require a PR and passing status checks |

Also update `github_repository` in `bootstrap/variables.tf` to your real
`owner/repo` and re-apply bootstrap — the OIDC trust policy restricts role
assumption to that exact repository.

## 5. Deploy dev

```bash
cd environments/dev
terraform init -backend-config=backend.hcl
terraform plan -var-file=dev.tfvars -out=dev.tfplan
terraform apply dev.tfplan

curl "$(terraform output -raw application_url)/health"
```

Expect `{"status":"healthy"}`.

## 6. Verify against AWS, not just state

```bash
# Database must not be public
aws rds describe-db-instances \
  --query 'DBInstances[].{id:DBInstanceIdentifier,public:PubliclyAccessible,encrypted:StorageEncrypted}'

# Tasks must have no public IP
aws ecs list-tasks --cluster $(terraform output -raw ecs_cluster_name)

# Targets must be healthy
aws elbv2 describe-target-health --target-group-arn <arn>
```

## 7. Plan staging and prod (no apply)

```bash
cd ../staging && terraform init -backend-config=backend.hcl && terraform plan -var-file=staging.tfvars
cd ../prod    && terraform init -backend-config=backend.hcl && terraform plan -var-file=prod.tfvars
```

This proves both configurations are valid and deployable without spending
money on them.

## 8. Tear down when you are done

```bash
cd environments/dev
terraform destroy -var-file=dev.tfvars
```

NAT Gateway and RDS accrue charges around the clock — destroy dev whenever you
are not actively working on it.

## Quality gates locally

```bash
pip install --user pre-commit checkov
pre-commit install
pre-commit run --all-files

make fmt lint sec test
```
