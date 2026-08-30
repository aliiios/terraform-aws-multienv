#!/usr/bin/env bash
# =============================================================================
# One-time repository initialisation.
#
#   ./init-repo.sh <github-username>
#
# Does two things:
#   1. Replaces aliiios placeholders with your real username.
#   2. Builds a phased git history instead of one giant "initial commit".
#
# Run this ONCE, from the repository root, BEFORE pushing.
# =============================================================================
set -euo pipefail

USERNAME="${1:-}"
if [[ -z "$USERNAME" ]]; then
  echo "usage: ./init-repo.sh <github-username>" >&2
  exit 1
fi

REPO="terraform-aws-multienv"

echo "==> Replacing placeholders with '$USERNAME'"
grep -rl "aliiios" . --exclude-dir=.git 2>/dev/null \
  | xargs -r sed -i "s|aliiios|${USERNAME}|g"

if [[ -d .git ]]; then
  echo "!! .git already exists. Remove it first if you want a fresh history:"
  echo "   rm -rf .git && ./init-repo.sh $USERNAME"
  exit 1
fi

echo "==> Building phased git history"
git init -q
git branch -M main

commit () { git commit -q -m "$1"; echo "    - $1"; }

git add .gitignore .gitattributes .editorconfig .tflint.hcl \
        .pre-commit-config.yaml Makefile LICENSE
commit "chore: repository skeleton, editor config and quality gate tooling"

git add bootstrap/
commit "feat(bootstrap): S3 remote state backend with KMS encryption and native locking"

git add modules/vpc/main.tf modules/vpc/variables.tf modules/vpc/outputs.tf \
        modules/vpc/versions.tf modules/vpc/README.md
commit "feat(vpc): three-tier VPC with NAT, gateway and interface endpoints"

git add modules/rds/main.tf modules/rds/variables.tf modules/rds/outputs.tf \
        modules/rds/versions.tf modules/rds/README.md
commit "feat(rds): private PostgreSQL with generated credentials in Secrets Manager"

git add modules/ecr/ app/
commit "feat(ecr): immutable-tag registry and containerised application"

git add modules/ecs/main.tf modules/ecs/variables.tf modules/ecs/outputs.tf \
        modules/ecs/versions.tf modules/ecs/README.md
commit "feat(ecs): Fargate service behind ALB with autoscaling and zero-downtime deploys"

git add environments/
commit "feat(environments): isolated dev, staging and prod root modules"

git add modules/vpc/tests/ modules/rds/tests/ modules/ecs/tests/ tests/
commit "test: plan-time assertions for network isolation, encryption and deployment safety"

git add .github/
commit "ci: OIDC-authenticated plan and apply pipelines, drift detection, dependabot"

git add README.md SETUP.md CONTRIBUTING.md SECURITY.md docs/ architecture/
commit "docs: architecture, security model, cost analysis, ADRs and runbook"

git add -A
if ! git diff --cached --quiet; then
  commit "chore: remaining project files"
fi

echo
echo "==> Done. $(git rev-list --count HEAD) commits created."
echo
echo "Next:"
echo "  1. make validate-all          # MUST pass before pushing"
echo "  2. gh repo create $REPO --public --source=. --remote=origin --push"
echo "     (or create the repo on github.com and: git remote add origin ... && git push -u origin main)"
