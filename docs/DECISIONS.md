# Architecture Decision Records

Each record states the decision, the reasoning, and what was given up.

---

## ADR-001 — Separate root modules per environment, not workspaces

**Decision:** each environment is its own root module with its own state file.

**Reasoning:** workspaces share one configuration and one backend. That
prevents per-environment IAM boundaries, concentrates blast radius in a single
config, and forces environment differences into `terraform.workspace`
conditionals that become unreadable.

**Trade-off:** some duplication across `environments/*/`. Accepted, because the
duplicated files are thin composition layers — all real logic lives in shared
modules. Terragrunt would remove the duplication at the cost of an extra tool.

---

## ADR-002 — ECS Fargate, not ECS on EC2 or EKS

**Decision:** Fargate.

**Reasoning:** no host management, per-task isolation, and a cost model that
suits small variable workloads. EKS adds a $73/month control plane and
substantial operational surface for no benefit at this scale.

**Trade-off:** higher per-unit compute cost at sustained high load, no GPU or
custom kernel support, and less control over placement.

---

## ADR-003 — S3-native state locking, not DynamoDB

**Decision:** `use_lockfile = true` (Terraform ≥ 1.11).

**Reasoning:** removes an entire resource, its cost, and its IAM surface.
DynamoDB-based locking is the legacy pattern for new projects.

**Trade-off:** requires Terraform ≥ 1.11, which is enforced repository-wide.

---

## ADR-004 — Three subnet tiers, not two

**Decision:** public, private-app, and private-data tiers.

**Reasoning:** the data tier's route table contains only the local route. The
database has no path to the internet in either direction, eliminating a class
of exfiltration.

**Trade-off:** more subnets and route tables to manage. Minimal, and the
security benefit is disproportionate.

---

## ADR-005 — Checkov, not tfsec

**Decision:** Checkov as the policy scanner.

**Reasoning:** tfsec was deprecated and merged into Aqua's Trivy. Checkov has
the broadest rule coverage and the best PR integration. Trivy is a valid
alternative; tfsec is not.

**Trade-off:** Checkov is slower than tfsec was and produces more findings,
some requiring justified suppression.

---

## ADR-006 — Cross-module security group rule in the root module

**Decision:** the `rds` module ships a security group with no ingress; the
environment root module declares the rule allowing the ECS security group.

**Reasoning:** `rds` needing the ECS SG while `ecs` needs the RDS secret ARN is
a circular module dependency Terraform cannot resolve. Declaring the
cross-cutting rule in the module that already depends on both breaks the cycle.

**Trade-off:** the security posture is not fully described inside the `rds`
module. Documented in the module and in the root module comments.

---

## ADR-007 — Generated passwords in Secrets Manager, not SSM Parameter Store

**Decision:** AWS Secrets Manager.

**Reasoning:** native rotation support, native ECS task-definition integration
with per-JSON-key references, and cross-account resource policies.

**Trade-off:** ~$0.40/secret/month versus free standard SSM parameters. Worth
it for rotation capability and the first-class ECS integration.

---

## ADR-008 — Code all three environments, apply only dev

**Decision:** `staging` and `prod` are fully implemented and validated by
`terraform plan` on every PR, but never applied.

**Reasoning:** running all three would cost roughly $1,200/month on a personal
account for no additional learning. Correct, reviewable, plannable code
demonstrates the same competence.

**Trade-off:** staging and prod are not runtime-verified. Stated explicitly in
the README rather than implied otherwise.

---

## ADR-009 — Immutable ECR tags

**Decision:** `image_tag_mutability = "IMMUTABLE"`.

**Reasoning:** a mutable tag means the image in production is not provably the
image that was tested, and rollback targets are unreliable.

**Trade-off:** every change requires a new tag; no convenient `latest`.
That inconvenience is the mechanism working as intended.

---

## ADR-010 — Interface endpoints in staging/prod only

**Decision:** gateway endpoints (S3, DynamoDB) always; interface endpoints only
in staging and prod.

**Reasoning:** interface endpoints cost ~$7/month per AZ. In dev, where NAT
already exists and traffic volume is negligible, they add cost without
meaningful benefit. In staging and prod they are enabled for the security
property — AWS API traffic never leaves the VPC — not primarily for cost.

**Trade-off:** dev's network path differs slightly from prod's. Accepted, and
noted as a known limitation.
