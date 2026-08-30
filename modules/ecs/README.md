# ECS Module

Fargate service behind an internet-facing Application Load Balancer, with
autoscaling, logging and alarms.

## Security group chain

```
Internet  → ALB SG   (80/443 from 0.0.0.0/0 — the only internet-facing rule)
ALB SG    → ECS SG   (container port, by group reference)
ECS SG    → RDS SG   (5432, rule declared in the root module)
```

No CIDR ranges are used between tiers. Referencing a security group authorises
an identity rather than an address, so rules stay correct as tasks are
replaced and rescheduled.

## Task execution role vs task role

| | Task execution role | Task role |
|---|---|---|
| Used by | the ECS agent | your application code |
| Does | pull the image, fetch secrets, write logs | calls to S3, DynamoDB, SQS… |
| Timing | before and around the container | at runtime, inside the container |

Separating them means the application cannot pull arbitrary images or read
every secret in the account just because it needs to read one S3 bucket.

## Networking

Fargate requires `network_mode = "awsvpc"`: each task gets its own ENI and
private IP, which is why the target group must use `target_type = "ip"` rather
than instance targets.

## Zero-downtime deployment

`minimum_healthy_percent = 100`, `maximum_percent = 200`, circuit breaker with
rollback. New tasks start before old ones stop, must pass ALB health checks
before being registered, and connection draining lets in-flight requests
complete. A broken version never receives traffic and is rolled back
automatically.

## Two health checks, two purposes

- **Container health check** (task definition) — the ECS agent restarts an
  unhealthy container.
- **ALB target group health check** — the load balancer stops routing to an
  unhealthy target.

## Autoscaling

Target tracking on average CPU and memory. Scale-out cooldown is 60 seconds,
scale-in is 300: being slow to add capacity hurts users, being slow to remove
it only costs a little money.

`desired_count` is in `ignore_changes` because autoscaling owns that value at
runtime — otherwise every apply would undo it.
