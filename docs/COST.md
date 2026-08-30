# Cost Analysis

## Where the money actually goes

Ranked by monthly cost in a typical deployment of this architecture.

### 1. NAT Gateway — the one that surprises people

~$0.045/hour (~$33/month) **per gateway**, plus ~$0.045 per GB processed.
The hourly charge accrues whether or not any traffic flows.

- `dev`: one shared NAT — saves ~$66/month versus one per AZ, at the cost of an
  AZ-level single point of failure.
- `staging`/`prod`: one per AZ, so an AZ failure cannot sever egress.

Reduction levers: VPC endpoints for AWS API traffic; keeping traffic within its
own AZ (each AZ's route table points at its own NAT, avoiding cross-AZ charges);
a NAT *instance* on a small EC2 host for non-production, which is cheaper but
becomes your responsibility to patch, monitor and scale.

### 2. RDS

- `db.t4g.micro` single-AZ ≈ $13/month.
- `db.m6g.large` Multi-AZ ≈ $250/month.

Multi-AZ **doubles** the instance cost for a standby that serves no read
traffic — you are buying failover, not capacity. Storage is billed separately
per GB-month, and backups beyond the allocated storage size incur additional
charges. `gp3` is used because it decouples IOPS from volume size.

### 3. Fargate

Billed per vCPU-second and GB-second. Roughly $0.04/vCPU-hour and
$0.0045/GB-hour in `eu-west-3`.

- dev, 1 task at 0.25 vCPU / 0.5 GB ≈ $9/month
- prod, 3 tasks at 1 vCPU / 2 GB ≈ $110/month

Reduction levers: right-size CPU and memory using Container Insights data
rather than guessing; use Fargate Spot for fault-tolerant workloads (up to ~70%
cheaper, tasks reclaimed with 2 minutes' notice); let autoscaling scale in
during quiet periods; use ARM64 (Graviton) tasks, which are cheaper per unit of
performance.

### 4. VPC Interface Endpoints

~$0.01/hour **per endpoint per AZ**, plus ~$0.01/GB processed.

Seven endpoints × 3 AZs ≈ $150/month. This is why `dev` disables them.

**Break-even reasoning:** an interface endpoint costs ~$7/month per AZ. NAT
processing costs ~$0.045/GB. Below roughly 150 GB/month of traffic to that
service, NAT is cheaper. Above it, the endpoint wins.

But cost is not the only axis: endpoints also remove a dependency on NAT and
keep AWS API traffic off the public internet entirely. In staging and prod they
are enabled for that reason, not for cost.

Gateway endpoints (S3, DynamoDB) are **free** and should always be created.

### 5. ALB

~$0.025/hour (~$18/month) plus LCU charges based on connections, requests and
bandwidth. Consolidating multiple services behind one ALB using host- or
path-based listener rules amortises the fixed cost.

### 6. CloudWatch

Billed for log ingestion (~$0.50/GB), storage, and custom metrics. Container
Insights generates a substantial number of metrics.

The most common cost leak is unbounded log retention. Every log group in this
project sets an explicit `retention_in_days`.

### 7. S3 and KMS

Terraform state is kilobytes. The customer-managed KMS key costs $1/month flat
plus per-request charges, largely mitigated by `bucket_key_enabled`. ALB access
logs grow with traffic and are expired by a lifecycle rule.

## Estimated totals

| Environment | Monthly |
|---|---|
| dev | ~$76 |
| staging | ~$400 |
| prod | ~$700 |

Only `dev` is applied in this project.

## Practical cost hygiene

- `terraform destroy` the dev environment when you are not actively working.
  NAT and RDS accrue charges around the clock.
- Set a CloudWatch billing alarm before the first apply, not after the bill.
- Infracost runs on every PR and posts the monthly delta, so cost is reviewed
  alongside the code that causes it.
- Tag everything: `default_tags` in the provider ensures every resource carries
  Project, Environment and ManagedBy, which is what makes Cost Explorer useful.

## FinOps framing

Cost is a design constraint, not an afterthought. Every architectural choice in
this project has a price: Multi-AZ buys availability, endpoints buy security,
autoscaling buys elasticity. Being able to state what each one costs and what
it buys is the difference between an engineer who designs systems and one who
only assembles them.
