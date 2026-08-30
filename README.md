# Multi-Environment AWS Infrastructure with Terraform

[![Terraform](https://img.shields.io/badge/terraform-%3E%3D1.11-7B42BC?logo=terraform)](https://www.terraform.io)
[![AWS Provider](https://img.shields.io/badge/AWS%20provider-~%3E6.0-FF9900?logo=amazonwebservices)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

<!-- Uncomment once CI has run green at least once. A red badge is worse than no badge.
[![Terraform CI](https://github.com/aliiios/terraform-aws-multienv/actions/workflows/terraform-ci.yml/badge.svg)](https://github.com/aliiios/terraform-aws-multienv/actions/workflows/terraform-ci.yml)
-->

Production-style, modular AWS infrastructure provisioned entirely with Terraform:
a three-tier VPC, a containerised application on ECS Fargate behind an
Application Load Balancer, a private PostgreSQL database on RDS, secrets in AWS
Secrets Manager, CI/CD through GitHub Actions authenticated with OIDC, native
infrastructure tests, autoscaling, and observability — across three isolated
environments.

---

## 1. Architecture

<!-- Export a diagram from draw.io (AWS 2024 shape library) to
     architecture/network.png and uncomment the line below.
![Network architecture](architecture/network.png)
-->

```
                              Internet
                                 │
                                 ▼
                       ┌──────────────────┐
                       │ Internet Gateway │
                       └──────────────────┘
                                 │
      ┌──────────────────────────┴──────────────────────────┐
      │                   PUBLIC TIER                        │
      │   AZ-a                                    AZ-b       │
      │   ┌───────────────┐              ┌───────────────┐   │
      │   │      ALB      │◄────────────►│      ALB      │   │
      │   │  NAT Gateway  │              │  NAT Gateway  │   │
      │   └───────────────┘              └───────────────┘   │
      └──────────┬──────────────────────────────┬────────────┘
                 │                              │
      ┌──────────▼──────────────────────────────▼────────────┐
      │              PRIVATE APPLICATION TIER                 │
      │   ┌───────────────┐              ┌───────────────┐   │
      │   │ ECS Fargate   │              │ ECS Fargate   │   │
      │   │    tasks      │              │    tasks      │   │
      │   └───────┬───────┘              └───────┬───────┘   │
      │           │   no public IP, egress via NAT           │
      └───────────┼──────────────────────────────┼────────────┘
                  │                              │
      ┌───────────▼──────────────────────────────▼────────────┐
      │                 PRIVATE DATA TIER                      │
      │   ┌──────────────────────────────────────────────┐    │
      │   │   RDS PostgreSQL  (Multi-AZ in staging/prod)  │    │
      │   │   NO route to NAT.  NO route to IGW.          │    │
      │   └──────────────────────────────────────────────┘    │
      └────────────────────────────────────────────────────────┘

              AWS API traffic stays inside the VPC
      ┌───────────────────┬────────────────┬──────────────────┐
      │  Gateway endpoints│  Interface endpoints (PrivateLink) │
      │  S3, DynamoDB     │  ECR API, ECR DKR, Secrets Manager,│
      │  (free)           │  CloudWatch Logs, STS, SSM         │
      └───────────────────┴────────────────────────────────────┘
```

### Traffic flow

1. A client resolves the ALB DNS name and connects on port 80/443.
2. The ALB (public subnets, spanning ≥2 AZs) terminates the connection and
   forwards to a healthy target.
3. Targets are Fargate task **IP addresses** in the private application
   subnets. Tasks have no public IP and cannot be reached directly.
4. The task connects to RDS on port 5432. The database's security group
   permits *only* the ECS task security group.
5. The task fetches its DB credentials from Secrets Manager and writes logs to
   CloudWatch — both through VPC interface endpoints where enabled, so that
   traffic never leaves the VPC.

---

## 2. Repository layout

```
.
├── bootstrap/              S3 state bucket + KMS key + GitHub OIDC role (LOCAL state)
├── modules/
│   ├── vpc/                Network: VPC, 3 subnet tiers, NAT, routing, endpoints, flow logs
│   ├── ecr/                Container registry with immutable tags + lifecycle policy
│   ├── rds/                Database, subnet group, SG, generated password, Secrets Manager
│   └── ecs/                Cluster, task definition, service, ALB, IAM roles, autoscaling
├── environments/
│   ├── dev/                Root module + its own state + dev.tfvars
│   ├── staging/            Root module + its own state + staging.tfvars
│   └── prod/               Root module + its own state + prod.tfvars
├── app/                    Minimal containerised application + Dockerfile
├── tests/                  Test documentation (suites live in modules/*/tests/)
├── docs/                   Security model, cost analysis, runbook, interview prep
├── .github/workflows/      CI (plan/test/scan/cost), CD (apply), drift detection
├── .pre-commit-config.yaml Local quality gates
├── .tflint.hcl             Linting rules
└── Makefile                Convenience targets
```

---

## 3. Deployment status (read this before reviewing)

| Environment | Code | `terraform validate` + `plan` | Applied to AWS |
|---|---|---|---|
| `dev` | complete | yes | no |
| `staging` | complete | yes | no |
| `prod` | complete | yes | no |

This repository is the **infrastructure definition**. All three environments are
fully implemented and validated with `terraform validate` and `terraform plan`;
none are currently deployed, to avoid ongoing cost on a personal AWS account
(the `dev` environment alone runs ~$76/month, dominated by NAT Gateway and ALB
hourly charges that accrue whether or not traffic flows).

The distinction is stated rather than glossed over: `plan` proves the
configuration is internally consistent and accepted by the AWS APIs. It does
**not** prove runtime behaviour — that the application responds, that end-to-end
connectivity works, that failover succeeds. Deploying requires no code changes,
only `terraform apply`.

## 4. Getting started

### Prerequisites

| Tool | Minimum | Why |
|---|---|---|
| Terraform | **1.11** | `use_lockfile` (S3-native state locking) |
| AWS CLI | 2.x | modern command surface |
| Podman or Docker | any | building the application image |
| tflint, Checkov, terraform-docs, Infracost, pre-commit | latest | quality gates |

> **On scanners:** this project uses **Checkov**. `tfsec` was deprecated and
> folded into Aqua's **Trivy**; either Checkov or Trivy is a current choice,
> `tfsec` is not.

### Step 1 — Bootstrap (once)

```bash
cd bootstrap
terraform init          # local state; no bucket needed yet
terraform apply
terraform output state_bucket_name
terraform output github_actions_role_arn
```

This creates the S3 state bucket, its KMS key, and the GitHub Actions OIDC
role. It uses **local state permanently** — see §6.

### Step 2 — Wire the backend

The backends use **partial configuration**: the bucket name is account-specific
and is supplied at init time rather than committed to the repository.

```bash
BUCKET=$(cd bootstrap && terraform output -raw state_bucket_name)
for ENV in dev staging prod; do
  sed "s/REPLACE-WITH-YOUR-STATE-BUCKET/$BUCKET/" \
    environments/$ENV/backend.hcl.example > environments/$ENV/backend.hcl
done
```

`backend.hcl` is gitignored; the committed `.example` documents the required
keys. Initialise with `terraform init -backend-config=backend.hcl`.

Backend blocks cannot reference variables — Terraform resolves the backend
before variables are evaluated — which is why partial configuration is the
supported mechanism rather than a `var.` reference.

### Step 3 — Configure GitHub

Repository → Settings:
- **Variables** → `AWS_ROLE_ARN` = the `github_actions_role_arn` output.
- **Secrets** → `INFRACOST_API_KEY` (free tier available).
- **Environments** → create `dev`, `staging`, `prod`; add required reviewers on
  `staging` and `prod`.
- **Branches** → protect `main`: require a PR and passing status checks.

### Step 4 — Deploy dev

```bash
cd environments/dev
terraform init -backend-config=backend.hcl
terraform plan  -var-file=dev.tfvars -out=dev.tfplan
terraform apply dev.tfplan
curl "$(terraform output -raw application_url)/health"
```

### Step 5 — Push your own image (optional)

See [`app/README.md`](app/README.md), then set `container_image` in
`dev.tfvars` to the pushed ECR reference and re-apply.

### Step 6 — Tear down when finished

```bash
cd environments/dev && terraform destroy -var-file=dev.tfvars
```

The bootstrap bucket is protected by `prevent_destroy` and will refuse to be
deleted — intentionally.

---

## 5. AWS services and why each one is here

| Service | Role in this architecture | Why not the alternative |
|---|---|---|
| **VPC** | Network isolation, three tiers across AZs | Default VPC has no tiering and public subnets everywhere |
| **ECS Fargate** | Runs containers without managing servers | ECS on EC2 means patching, scaling and securing the hosts yourself |
| **ECR** | Private image registry with immutable tags + scanning | Docker Hub is public, rate-limited, and outside your IAM boundary |
| **ALB** | Layer 7 routing, HTTP health checks, TLS termination | NLB is L4 and cannot make HTTP-aware decisions |
| **RDS PostgreSQL** | Managed database: backups, patching, Multi-AZ failover | Self-managed on EC2 means you own backup/restore/failover |
| **Secrets Manager** | Generated credentials, injected at task start | Plaintext env vars are visible via `DescribeTaskDefinition` |
| **VPC Endpoints** | AWS API traffic never traverses the public internet | NAT-only means AWS API calls leave the VPC and incur data charges |
| **CloudWatch** | Logs, metrics, Container Insights, alarms | Without it, a failing task is invisible |
| **Application Auto Scaling** | Target-tracking on CPU and memory | Static capacity either wastes money or falls over |
| **S3** | Terraform state, ALB access logs | — |
| **KMS** | Customer-managed encryption of state | The AWS-managed key gives no rotation control or usage audit |
| **IAM + STS** | Roles, least privilege, OIDC federation | Static keys don't expire and are the top leak vector |

---

## 6. Key design decisions

### 6.1 Separate root modules and separate state — not workspaces

**Decision:** each environment is its own root module with its own state file.

Terraform workspaces share a single configuration and a single backend,
differing only by a `terraform.workspace` value. Three problems follow:

1. **Blast radius.** One configuration means one place to make a mistake that
   reaches every environment.
2. **Permissions.** You cannot grant an engineer access to dev state but not
   prod state when both live under one backend configuration.
3. **Divergence.** Real environments differ (Multi-AZ, endpoint counts, AZ
   count). Expressing that with `count = terraform.workspace == "prod" ? …`
   conditionals produces code nobody can read or safely change.

Separate root modules give genuine isolation: `prod` state is a different S3
object with a different IAM boundary, and `prod` can be applied without
touching `dev` at all. Environment differences live in `.tfvars` values, not
in conditional logic, so all three environments follow the *same* code path.

Workspaces remain a good fit for short-lived, structurally identical stacks —
per-developer sandboxes or per-PR ephemeral environments.

### 6.2 Fargate over ECS on EC2

| | Fargate | ECS on EC2 |
|---|---|---|
| Host management | none | you patch, scale, secure |
| Cost model | per task per second | per instance-hour |
| Cost at high steady load | higher | lower (with good bin-packing) |
| Cost at low/variable load | lower | you pay for idle instances |
| GPU / custom kernel | not available | available |
| Isolation | per-task micro-VM | shared host kernel |

**Decision: Fargate.** The workload is small and variable, host management is
undifferentiated work, and per-task isolation is a security win. If this
application later ran hundreds of steady tasks, EC2 with Savings Plans or
Fargate Spot would be worth revisiting.

### 6.3 S3-native locking instead of DynamoDB

State locking prevents two concurrent applies from corrupting the same state.

- **Historically:** an S3 backend plus a separate DynamoDB table holding lock
  records — an extra resource to create, pay for, and grant IAM access to.
- **Now (Terraform ≥ 1.11):** `use_lockfile = true` makes Terraform write a
  `<key>.tflock` object into the same S3 bucket. One fewer resource, one fewer
  failure mode.

**Decision:** S3-native lockfile. This is also why `required_version >= 1.11`
is enforced everywhere.

### 6.4 Three subnet tiers instead of two

The data tier's route table contains **only the local VPC route** — no NAT, no
IGW. The database therefore cannot reach the internet in either direction.

A two-tier design puts the database in the same subnets as the application,
inheriting a NAT route it never needs. Removing that route eliminates an entire
exfiltration path: even a fully compromised database cannot call out.

### 6.5 Security groups reference groups, never CIDRs, between tiers

```
ALB SG  ← 0.0.0.0/0 on 80/443        (the only internet-facing rule)
ECS SG  ← ALB SG on the container port
RDS SG  ← ECS SG on 5432
```

Referencing a security **group** authorises an identity, not an address range.
Tasks can be replaced, rescheduled, or moved to different subnets and the rule
stays correct. A CIDR-based rule between tiers would have to be widened every
time the network changed — and widening is how `0.0.0.0/0` ends up on a
database.

### 6.6 The cross-module security group rule lives in the root module

`rds` would need the ECS security group ID; `ecs` needs the Secrets Manager ARN
from `rds`. That is a **circular module dependency**, which Terraform cannot
resolve.

The fix is standard: the `rds` module ships a security group with **no ingress
rules at all**, and the environment root module — which already depends on both
— declares the single cross-cutting rule. See `environments/*/main.tf`.

### 6.7 Secrets are generated, never supplied

```
random_password  →  Secrets Manager secret  →  ECS task definition `secrets` block
                                                        ↓
                              injected as env vars at task START by the
                              TASK EXECUTION ROLE, using ARN + JSON key
```

No password appears in `.tfvars`, in Git, in the task definition, or in logs.
The generated value *is* written to Terraform state — which is exactly why the
state bucket is KMS-encrypted, versioned, and public-access-blocked.

### 6.8 Immutable image tags

With mutable tags, `app:v1.2.0` can be overwritten by different content — so
the image in production is not provably the image you tested, and "rollback to
v1.2.0" may not restore what you expect. `IMMUTABLE` makes a tag permanently
identify one digest.

---

## 7. Task execution role vs task role

The most commonly confused pair in ECS.

| | **Task execution role** | **Task role** |
|---|---|---|
| Used by | the ECS agent (AWS-managed infrastructure) | your application code |
| When | before and around your container | at runtime, inside your container |
| Typical permissions | `ecr:GetDownloadUrlForLayer`, `secretsmanager:GetSecretValue`, `logs:PutLogEvents` | `s3:GetObject`, `dynamodb:Query`, `sqs:SendMessage` |
| How it is obtained | assumed by ECS on your behalf | via the container credential endpoint, picked up automatically by the AWS SDK |

They are separate so platform permissions and application permissions do not
merge. Your application can read one S3 bucket without also being able to pull
arbitrary images or read every secret in the account.

---

## 8. VPC endpoints — the ECR detail people get wrong

| | Gateway endpoint | Interface endpoint |
|---|---|---|
| Services | S3, DynamoDB only | almost everything else |
| Mechanism | route table entry with a prefix list | an ENI with a private IP (PrivateLink) |
| DNS | none needed | private DNS overrides the public hostname |
| Hourly cost | **free** | ~$0.01/hour **per AZ** + per-GB |

Pulling a container image is **two operations**:

1. ECS calls the **ECR API** for an auth token and the image manifest →
   `ecr.api` interface endpoint.
2. ECS downloads the image **layers**, which ECR stores in **S3** →
   **S3 gateway endpoint**.

Create the ECR interface endpoints but forget the S3 gateway endpoint and image
pulls still leave through NAT — or fail outright in a subnet without one. This
is the single most common VPC endpoint mistake.

Interface endpoints also require `enable_dns_support` **and**
`enable_dns_hostnames` on the VPC. Without both, the AWS service hostname keeps
resolving to a public IP and your traffic silently exits via NAT — the endpoint
appears healthy while doing nothing.

**Endpoints are not automatically cheaper.** Roughly: ~$7/month per interface
endpoint per AZ versus $0.045/GB of NAT processing. Below ~150 GB/month of AWS
API traffic per endpoint, NAT is cheaper. Above it, endpoints win — and they
are the more *secure* option regardless of cost, which is why they are enabled
in staging and prod but not in dev.

---

## 9. Zero-downtime deployment

Configuration: `minimum_healthy_percent = 100`, `maximum_percent = 200`,
deployment circuit breaker with rollback enabled.

```
Steady state           3 tasks (v1) — all registered and healthy
Deployment starts      ECS launches 3 tasks (v2)  → up to 6 running
New tasks boot         health_check_grace_period_seconds gives them 60s
ALB probes /health     2 consecutive 200s → target marked healthy
Traffic shifts         ALB load-balances across healthy v1 and v2 targets
Old tasks drain        deregistered; in-flight requests get deregistration_delay
                       seconds to complete (connection draining)
Old tasks stop         steady state: 3 tasks (v2)
```

Capacity never drops below 100%, so no request is dropped.

**If the new version is broken:** v2 tasks fail their health checks and are
never registered with the target group, so they never receive traffic. v1 keeps
serving throughout. The circuit breaker detects the repeated failures and
automatically rolls the service back to the previous task definition revision.
Users see nothing.

Two distinct health checks are in play, and the distinction matters:
- **Container health check** (in the task definition) — evaluated by the ECS
  agent; a failure causes ECS to **restart the container**.
- **ALB target group health check** — evaluated by the load balancer; a failure
  causes the ALB to **stop routing** to that target.

---

## 10. CI/CD

```
Pull request                              Merge to main
     │                                          │
     ├─ terraform fmt -check                    ├─ GitHub OIDC → assume IAM role
     ├─ tflint                                  ├─ terraform init
     ├─ Checkov                                 ├─ terraform plan -out=tfplan
     ├─ terraform test  (vpc, rds, ecs)         └─ terraform apply tfplan
     ├─ terraform plan  (dev, staging, prod)          (dev only; staging/prod
     ├─ plan posted as a PR comment                    behind manual approval)
     └─ Infracost cost delta comment
```

### OIDC — how CI authenticates without stored keys

1. The workflow requests a signed JWT from GitHub's OIDC issuer
   (`token.actions.githubusercontent.com`). This requires
   `permissions: id-token: write`.
2. It calls `sts:AssumeRoleWithWebIdentity` with that token.
3. AWS validates the signature against the registered OIDC provider.
4. AWS evaluates the role's **trust policy** conditions:
   - `aud` must equal `sts.amazonaws.com`
   - `sub` must match `repo:<owner>/<repo>:ref:refs/heads/main` or
     `repo:<owner>/<repo>:pull_request`
5. STS returns credentials that expire when the job ends.

**The `sub` condition is the critical line.** Without it, *any* GitHub
repository on the internet could assume the role. Restricting the subject claim
is what binds the role to your repository and branch.

No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` exists anywhere in this
repository or its settings.

### Preventing a bad change from reaching production

Six independent gates: branch protection on `main` → required status checks →
Checkov policy scan → `terraform test` assertions → human review of the posted
plan → a GitHub Environment approval before any staging/prod apply. Apply runs
against a **saved plan file**, so what is applied is exactly what was reviewed.

---

## 11. Testing

Suites live in `modules/*/tests/*.tftest.hcl` and run with `terraform test`.

They encode security requirements as executable assertions:

- RDS is never publicly accessible
- RDS storage is encrypted
- Fargate tasks never get public IPs and always run in private subnets
- Task role and execution role are distinct identities
- Target group uses `target_type = "ip"` (required for Fargate)
- Deployment settings guarantee zero downtime and automatic rollback
- Interface endpoints have private DNS enabled
- Log groups always have a finite retention

All assertions use `command = plan`: no resources are created, nothing costs
money, and the suite finishes in seconds. This is the correct level for
structural invariants.

**Terratest** would be the right tool only for runtime properties a plan cannot
know — can the task actually reach the database, does failover work, does the
endpoint return 200. That belongs in a scheduled pipeline against a throwaway
environment, not on every pull request.

---

## 12. Observability

| Signal | Source | Purpose |
|---|---|---|
| Container logs | `awslogs` driver → CloudWatch Logs | application-level debugging |
| Container Insights | ECS → CloudWatch | per-task CPU, memory, network, task counts |
| ALB access logs | ALB → S3 | per-request forensics, latency, client IPs |
| RDS Enhanced Monitoring | agent on the DB host | OS-level metrics at up to 1s granularity |
| Performance Insights | RDS | query-level performance, wait-event analysis |
| VPC Flow Logs | VPC → CloudWatch | "why can't A reach B", security forensics |
| Alarms | CloudWatch | unhealthy targets, elevated 5xx |

Standard RDS CloudWatch metrics come from the **hypervisor** at 60-second
granularity. Enhanced Monitoring runs an agent **inside the DB host** and can
attribute CPU to individual processes — something hypervisor metrics can never
do.

---

## 13. Cost

Rough `eu-west-3` monthly estimates. Actual figures come from Infracost on each PR.

### dev (the applied environment)

| Component | Estimate |
|---|---|
| NAT Gateway ×1 | ~$33 |
| ALB | ~$18 |
| Fargate 1 × 0.25 vCPU / 0.5 GB | ~$9 |
| RDS `db.t4g.micro`, 20 GB gp3, single-AZ | ~$14 |
| S3 + KMS + CloudWatch | ~$2 |
| **Total** | **~$76/month** |

### prod (coded, not applied)

| Component | Estimate |
|---|---|
| NAT Gateway ×3 | ~$99 |
| Interface endpoints (7 × 3 AZs) | ~$150 |
| ALB | ~$20 |
| Fargate 3 × 1 vCPU / 2 GB | ~$110 |
| RDS `db.m6g.large` Multi-AZ, 100 GB | ~$290 |
| CloudWatch, S3, KMS | ~$40 |
| **Total** | **~$700/month** |

### The main cost lessons

- **NAT Gateway is the surprise.** ~$33/month *per gateway* before a single
  byte moves, plus $0.045/GB processed. One NAT in dev, one per AZ in prod, is
  a deliberate availability-versus-cost trade.
- **VPC endpoints are not free and not automatically cheaper.** Seven interface
  endpoints across three AZs cost more than the NAT they partially replace.
  They are enabled in staging/prod for the **security** benefit; the break-even
  on cost alone is roughly 150 GB/month per endpoint.
- **Multi-AZ RDS doubles the instance cost** for a standby that serves no read
  traffic. You are buying failover, not capacity.
- **CloudWatch Logs bills for ingestion and storage.** Unbounded retention is a
  slow, invisible cost leak, which is why every log group here has an explicit
  retention.

---

## 14. Reliability

| Failure | What happens |
|---|---|
| One AZ fails | ALB stops routing to that AZ; ECS reschedules tasks in the surviving AZ; Multi-AZ RDS fails over to the standby (typically 60–120s) |
| A task crashes | The ECS service controller replaces it to restore `desired_count` |
| A task is unhealthy but alive | ALB deregisters it; ECS restarts the container |
| A bad deployment | New tasks fail health checks, are never registered, and the circuit breaker rolls back automatically |
| RDS primary fails | Multi-AZ promotes the standby; the DNS endpoint is repointed — applications reconnect without a config change |
| State bucket unavailable | Terraform cannot plan or apply; running infrastructure is unaffected. Versioning allows recovery from corruption |
| CI compromised | The OIDC role is scoped by subject claim to this repository; credentials are short-lived; `main` requires review |

**RTO / RPO for the data tier:** with Multi-AZ, RTO is on the order of minutes
(automatic failover) and RPO is effectively zero (synchronous replication).
With automated backups and point-in-time recovery, RPO for a restore is ~5
minutes, RTO measured in tens of minutes depending on database size.

> A backup that has never been restored is not a backup. Restore testing is
> listed in `docs/RUNBOOK.md` as an operational practice this project defines
> but has not exercised.

---

## 15. Documentation

- [`docs/SECURITY.md`](docs/SECURITY.md) — full security model, threat notes, known gaps
- [`docs/COST.md`](docs/COST.md) — detailed cost breakdown and optimisation levers
- [`docs/RUNBOOK.md`](docs/RUNBOOK.md) — operations, troubleshooting, incident response
- [`docs/INTERVIEW.md`](docs/INTERVIEW.md) — defense and interview preparation
- [`docs/DECISIONS.md`](docs/DECISIONS.md) — architecture decision records

---

## 16. Known limitations

Stated deliberately — an architecture document that claims no weaknesses is not
credible.

1. **Single AWS account.** Environment isolation is by VPC, state key and IAM
   policy, not by account boundary. AWS Organizations with an account per
   environment is the stronger model (see §17).
2. **No environment is currently deployed.** All three are plan-verified, not runtime-verified. See §3.
3. **The CI IAM role uses `PowerUserAccess`** plus a narrow IAM policy. This is
   broader than true least privilege. Scoping it to the exact actions and
   resource ARNs the modules touch is the next hardening step.
4. **HTTP by default in dev.** HTTPS requires an ACM certificate and a domain;
   the code path exists and activates by setting `certificate_arn`.
5. **No secret rotation.** Secrets Manager supports automatic rotation via
   Lambda; this project stores credentials but does not rotate them.
6. **No WAF.** A production internet-facing ALB would sit behind AWS WAF.
7. **Bootstrap local state has no remote backup.** By design it cannot use the
   bucket it creates; a manual copy of `bootstrap/terraform.tfstate` is the
   mitigation.

---

## 17. Future evolution

```
                    AWS Organizations
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
  Dev Account       Staging Account      Prod Account
        │                  │                  │
        └────────── cross-account IAM role assumption
                           │
                  Shared services account
                  (Terraform state, ECR, CI)
```

The strongest form of environment isolation is an **account boundary**: an IAM
mistake in dev cannot reach prod, service quotas are per-account, and billing
separates naturally. The migration path is mechanical — each environment's
provider block gains an `assume_role` targeting its account, and the state
bucket moves to a shared services account.

Also on the roadmap: AWS WAF, Secrets Manager rotation, ACM + Route 53 for
HTTPS, blue/green deployments via CodeDeploy, Aurora Serverless v2 for variable
database load, and codifying the developer workstation setup as an Ansible role.

---

## 18. License

MIT
