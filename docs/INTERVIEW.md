# Defense and Interview Preparation

Each answer below is the reasoning you should be able to give unprompted. Learn
the reasoning, not the wording.

---

## Architecture

**Walk me through the architecture.**
An internet-facing ALB in public subnets across two or more AZs receives
traffic and forwards it to Fargate tasks running in private application
subnets. Those tasks have no public IP. They connect to a PostgreSQL RDS
instance in a third, fully isolated subnet tier whose route table has no path
to NAT or the Internet Gateway. AWS API traffic — ECR, Secrets Manager,
CloudWatch, STS — stays inside the VPC through VPC endpoints. Everything is
defined in Terraform modules composed by three independent root modules, one
per environment, each with its own state.

**Why three subnet tiers?**
The data tier's route table contains only the local VPC route. The database
cannot reach the internet in either direction. A two-tier design would put the
database in subnets that have a NAT route it does not need, leaving an
exfiltration path open for no benefit.

**Why Fargate rather than EC2 or EKS?**
Fargate removes host management entirely and isolates each task in its own
micro-VM. EKS would add a control-plane cost and significant operational
surface for a workload of this size. ECS on EC2 would be cheaper at sustained
high load with good bin-packing, but makes patching, scaling and securing the
hosts my problem.

**Why an ALB rather than an NLB?**
The ALB operates at Layer 7: it can route on host, path and header, terminate
TLS, and run HTTP health checks. An NLB is Layer 4 — faster, preserves client
IP at the TCP level, but cannot make HTTP-aware decisions. I need HTTP health
checks and path routing.

**What happens if an Availability Zone fails?**
The ALB stops routing to targets in that AZ. The ECS service reschedules the
lost tasks in the surviving AZ. If RDS is Multi-AZ, it fails over to the
synchronous standby, typically within one to two minutes, and the DNS endpoint
is repointed so the application reconnects without a configuration change. In
dev, where a single NAT Gateway is shared, losing that AZ would sever egress —
a deliberate cost trade-off, which is why production uses one NAT per AZ.

---

## Terraform

**What is Terraform state and why does it exist?**
State maps resources declared in configuration to real resource identifiers in
the provider. Terraform needs it to know that `aws_instance.web` corresponds to
`i-0abc123`, to detect drift by comparing recorded attributes against reality,
and to build the dependency graph for ordering operations. Without state,
Terraform could not tell the difference between creating a new resource and
updating an existing one.

**What is state locking, and how is it implemented here?**
A lock prevents two concurrent operations from writing the same state file and
corrupting it. This project uses S3-native locking via `use_lockfile = true`,
available from Terraform 1.11, which writes a `.tflock` object into the same
bucket. The older approach required a separate DynamoDB table; that is now
unnecessary.

**Why separate state per environment rather than workspaces?**
Blast radius, permissions and clarity. Separate state means a prod IAM
boundary can differ from dev, an error in one config cannot touch another
environment, and environment differences are expressed as data in `.tfvars`
rather than as `terraform.workspace` conditionals scattered through the code.
Workspaces are well suited to short-lived, structurally identical stacks like
per-PR sandboxes.

**What causes drift, and how do you handle it?**
Manual console changes, changes by other automation, or AWS-side default
changes. Detection is a `terraform plan` with `-detailed-exitcode`, which this
project runs weekly and turns into a GitHub issue. Resolution is either to
revert the manual change, or to codify it if it was correct, or to `import` a
resource that was created outside Terraform.

**What happens during `terraform plan`?**
Terraform loads configuration and state, refreshes state by reading current
resource attributes from the provider, builds a dependency graph, and computes
the difference between desired and actual. It produces a set of create, update,
replace and destroy actions. It changes nothing.

**Why do child modules not contain a provider block?**
Child modules declare which providers they require; the root module configures
them and the child inherits that configuration. Putting a provider block in a
child module hard-codes its configuration, breaks reuse, and prevents the
caller from passing aliased providers for multi-region or multi-account work.

**How did you handle the circular dependency between ECS and RDS?**
RDS would need the ECS security group ID to allow inbound traffic, and ECS
needs the Secrets Manager ARN from RDS. That is a cycle Terraform cannot
resolve. The RDS module therefore ships a security group with no ingress rules,
and the environment root module — which already depends on both modules —
declares the single cross-cutting ingress rule.

**Why is `desired_count` in `ignore_changes`?**
Application Auto Scaling owns that value at runtime. Without the lifecycle
rule, every `terraform apply` would reset the service to the static configured
count and undo whatever scaling had decided.

---

## Security

**What is the difference between the task role and the task execution role?**
The execution role is used by the ECS agent — AWS-managed infrastructure —
before and around your container: pulling the image from ECR, fetching secrets
to inject, writing logs to CloudWatch. The task role is assumed by your
application code at runtime through the container credential endpoint, and is
what the AWS SDK inside the container uses. They are separate so platform
permissions and application permissions do not merge.

**Why is the database not publicly accessible, and what enforces that?**
`publicly_accessible = false` prevents a public IP being assigned. Beyond that,
the subnets it lives in have no route to an Internet Gateway, and its security
group only permits the ECS task security group. Three independent controls,
and a `terraform test` assertion that fails CI if any future change sets
`publicly_accessible` to true.

**Why security group references instead of CIDR ranges between tiers?**
A group reference authorises an identity rather than an address range. Tasks
can be replaced, rescheduled, or moved between subnets and the rule remains
correct. CIDR rules between tiers have to be widened whenever the network
changes, and widening is precisely how `0.0.0.0/0` ends up in front of a
database.

**How are database credentials handled?**
Terraform generates them with `random_password`, stores them in Secrets
Manager, and the ECS task definition references the secret ARN with a JSON key
path. ECS resolves the value at task start using the task execution role and
injects it as an environment variable. No password appears in tfvars, in Git,
or in the task definition. The generated value does land in Terraform state,
which is why state is KMS-encrypted, versioned and public-access-blocked.

**How does GitHub Actions authenticate to AWS, and why is that better?**
Via OIDC. The workflow requests a signed JWT from GitHub's issuer and exchanges
it through `sts:AssumeRoleWithWebIdentity` for credentials that expire at job
end. The role's trust policy restricts the audience to `sts.amazonaws.com` and
the subject claim to this repository on `main` or a pull request. Static access
keys never expire, are frequently leaked, and require manual rotation. The
subject condition is the critical part — without it, any repository on GitHub
could assume the role.

**Terraform state contains secrets. How is that handled?**
Accepted and mitigated rather than pretended away. The bucket blocks all public
access, enforces TLS through a bucket policy that denies non-secure transport,
encrypts objects with a customer-managed KMS key whose usage is logged in
CloudTrail, and versions every write. Access requires valid IAM credentials
with both S3 and KMS permissions.

---

## Networking

**Explain VPC endpoints, and the difference between the two types.**
Gateway endpoints exist only for S3 and DynamoDB. They are a route table entry
pointing at a prefix list — no ENI, no private IP, and no hourly cost.
Interface endpoints use PrivateLink: an actual ENI with a private IP in your
subnet, with private DNS overriding the public service hostname. They cost
roughly a cent per hour per AZ plus per-GB processing.

**What actually happens when ECS pulls an image from ECR?**
Two operations. First ECS calls the ECR API for an authorisation token and the
image manifest — that is the `ecr.api` interface endpoint. Then it downloads
the image layers, which ECR stores in S3 — that is the S3 gateway endpoint.
Creating the ECR interface endpoints but omitting the S3 gateway endpoint means
image pulls still go out through NAT, or fail entirely in a subnet without one.
It is a very common mistake.

**Are VPC endpoints always cheaper than NAT?**
No. An interface endpoint costs about $7 per month per AZ; NAT processing is
about $0.045 per GB. Below roughly 150 GB per month to that service, NAT is
cheaper. Above it, the endpoint wins. But cost is not the only consideration —
endpoints keep AWS API traffic off the public internet entirely, which is why
this project enables them in staging and prod for the security property, and
disables them in dev where the traffic volume does not justify the spend.

**Why must the VPC have DNS support and DNS hostnames enabled?**
Interface endpoints rely on private DNS to override the public AWS service
hostname. Without both settings, the hostname keeps resolving to a public IP
and traffic silently exits through NAT — the endpoint exists, looks healthy,
and does nothing.

---

## CI/CD and operations

**What happens on a pull request?**
Format check, tflint, Checkov policy scan, then `terraform test` for each
module, then `terraform plan` for all three environments in parallel. The plan
is posted as a PR comment and Infracost posts the monthly cost delta. Nothing
can change infrastructure — the most destructive operation is a read-only plan.

**How do you prevent a bad change from reaching production?**
Six independent gates: branch protection requiring a PR, required status
checks, the Checkov policy scan, the `terraform test` assertions, human review
of the posted plan, and a GitHub Environment approval before any staging or
prod apply. The apply step runs against a saved plan file, so what is applied
is exactly what was reviewed — no drift between plan and apply.

**Explain a zero-downtime deployment.**
Minimum healthy percent is 100 and maximum is 200, so ECS starts the new tasks
before stopping any old ones. New tasks must pass ALB health checks — two
consecutive successes — before being registered and receiving traffic. Only
then are the old tasks deregistered, and connection draining lets in-flight
requests complete during the deregistration delay. Capacity never falls below
100%.

**What if the new version is broken?**
The new tasks fail their health checks, are never registered with the target
group, and therefore never receive a single request. The old tasks keep
serving. The deployment circuit breaker detects the repeated failures and
automatically rolls back to the previous task definition revision. Users see
nothing.

**Why two different health checks?**
The container health check in the task definition is evaluated by the ECS agent
and causes ECS to restart an unhealthy container. The ALB target group health
check is evaluated by the load balancer and causes it to stop routing to an
unhealthy target. Different actors, different remedies.

---

## Cost

**What are the most expensive components, and why?**
In production: RDS Multi-AZ, then interface VPC endpoints, then Fargate, then
NAT Gateways. NAT is the one that surprises people — roughly $33 per month per
gateway before any traffic flows, plus per-GB processing.

**How would you reduce cost without weakening the architecture?**
Right-size Fargate tasks using real Container Insights data rather than
guesses. Use Fargate Spot for fault-tolerant workloads. Use ARM64 Graviton
tasks. Consolidate services behind a single ALB with listener rules. Reduce
CloudWatch retention. Buy Savings Plans for genuinely steady compute. And
destroy non-production environments when not in use.

---

## Questions about the project itself

**Why is only dev deployed?**
Cost control on a personal account. All three environments are fully
implemented and validated by `terraform plan` on every pull request, so the
code is proven correct and deployable. Running all three would cost roughly
$1,200 per month for no additional learning. I state the distinction explicitly
in the README: plan-verified is not the same as runtime-verified, and only dev
has been runtime-verified.

**What would you do differently at larger scale?**
Move to AWS Organizations with an account per environment, so isolation is an
account boundary rather than a logical one. Add AWS WAF in front of the ALB.
Enable Secrets Manager rotation. Adopt blue/green deployments through
CodeDeploy for instant rollback. Consider Aurora Serverless v2 if the database
load is variable. And codify the developer workstation setup so every engineer
starts from an identical environment.

**What is the weakest part of this design?**
The CI IAM role. It uses PowerUserAccess plus a narrow IAM policy, which is
broader than true least privilege. The right fix is to derive the exact action
list from CloudTrail after real usage and scope the policy to those actions and
specific resource ARNs. I chose to ship it broad and documented rather than
guess at a fine-grained policy before knowing what the modules actually call.
