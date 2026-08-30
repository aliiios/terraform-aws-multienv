# Operations Runbook

## Troubleshooting methodology

When something breaks, identify the **layer** before changing any code. Do not
reach for `terraform destroy` — it is a last resort, not a diagnostic.

```
Symptom
  │
  ├─ Does terraform plan/apply fail?        → Terraform / provider / IAM layer
  ├─ Does the resource exist in AWS?        → check with the AWS CLI, not state
  ├─ Is the task running?                   → ECS service events
  ├─ Is the container healthy?              → CloudWatch Logs + task stopped reason
  ├─ Is the target healthy?                 → ALB target group health
  ├─ Can the task reach the database?       → security groups, then routing
  └─ Is DNS resolving as expected?          → VPC DNS settings, endpoint private DNS
```

Terraform state describes what Terraform *believes*. Always verify against the
actual AWS API.

---

## Common failures

### ECS tasks start and immediately stop

```bash
aws ecs describe-services --cluster <cluster> --services <service> \
  --query 'services[0].events[:10]'

TASK=$(aws ecs list-tasks --cluster <cluster> --desired-status STOPPED \
  --query 'taskArns[0]' --output text)
aws ecs describe-tasks --cluster <cluster> --tasks $TASK \
  --query 'tasks[0].{stopped:stoppedReason,containers:containers[].reason}'
```

| `stoppedReason` | Cause |
|---|---|
| `CannotPullContainerError` | Image missing, wrong tag, or no route to ECR (check the S3 gateway endpoint) |
| `ResourceInitializationError: secrets` | The **task execution role** lacks `secretsmanager:GetSecretValue` for that ARN |
| `Essential container exited` | The application crashed — read the CloudWatch logs |
| `Task failed ELB health checks` | The health check path, port or grace period is wrong |

### Targets are unhealthy

```bash
aws elbv2 describe-target-health --target-group-arn <arn>
```

| `reason` | Cause |
|---|---|
| `Target.Timeout` | The container is not listening on the expected port, or the ECS security group does not allow the ALB |
| `Target.ResponseCodeMismatch` | The app returns a status outside the matcher |
| `Target.FailedHealthChecks` | The health path returns an error — check logs |
| `Target.NotRegistered` | The service has not registered targets yet, or the task is not running |

### The application cannot reach the database

Check in this order — the answer is almost always the first item:

1. **Security group.** Does the RDS security group have an ingress rule
   referencing the ECS task security group on 5432?
   ```bash
   aws ec2 describe-security-groups --group-ids <rds-sg> \
     --query 'SecurityGroups[0].IpPermissions'
   ```
2. **Subnets.** Is the DB subnet group using the private *data* subnets?
3. **Credentials.** Does the secret contain the expected JSON keys?
   ```bash
   aws secretsmanager get-secret-value --secret-id <name> \
     --query SecretString --output text | jq 'keys'
   ```
4. **Application config.** Is it reading `DB_HOST`, `DB_PORT`, `DB_NAME`?

Use ECS Exec to test from inside the task (dev only):
```bash
aws ecs execute-command --cluster <cluster> --task <task-id> \
  --container <name> --interactive --command "/bin/sh"
```

### Terraform state is locked

```
Error acquiring the state lock
```

Someone else is running Terraform, or a previous run was interrupted. Confirm
no run is in progress, then:

```bash
terraform force-unlock <LOCK_ID>
```

Forcing an unlock while another apply is genuinely running can corrupt state.
Verify first.

### `terraform plan` shows unexpected changes (drift)

Someone changed infrastructure outside Terraform. Options, in order of
preference:

1. **Revert the manual change** and let Terraform's plan go empty. Preferred:
   the code stays the source of truth.
2. **Codify the change** — update the Terraform to match reality if the change
   was correct.
3. **Import** if a resource was created manually:
   ```bash
   terraform import module.vpc.aws_subnet.public[0] subnet-xxxxx
   ```

The weekly drift-detection workflow opens an issue automatically when the dev
plan is non-empty.

---

## Routine operations

### Deploy a new application version

```bash
TAG=v1.2.0
podman build -t $REPO:$TAG ./app
podman tag $REPO:$TAG $ECR_URL:$TAG
podman push $ECR_URL:$TAG
# update container_image in dev.tfvars, then:
terraform plan -var-file=dev.tfvars -out=tfplan && terraform apply tfplan
```

Tags are immutable — you must bump the version. Pushing the same tag twice is
rejected, by design.

### Roll back

```bash
# Point the service at the previous task definition revision
aws ecs update-service --cluster <cluster> --service <service> \
  --task-definition <family>:<previous-revision>
```

Then revert `container_image` in the tfvars and apply, so the code matches
reality again. A rollback that is not reflected in code becomes drift.

### Retrieve database credentials

```bash
aws secretsmanager get-secret-value --secret-id <name> \
  --query SecretString --output text | jq .
```

### Restore the database to a point in time

```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier <id> \
  --target-db-instance-identifier <id>-restored \
  --restore-time 2026-01-15T10:00:00Z
```

This creates a **new instance**. Restoring in place is not possible; the
application must be repointed. Practise this before you need it — a backup that
has never been restored is not a backup.

### Recover Terraform state

The bucket is versioned:

```bash
aws s3api list-object-versions --bucket <bucket> --prefix dev/terraform.tfstate
aws s3api get-object --bucket <bucket> --key dev/terraform.tfstate \
  --version-id <id> restored.tfstate
```

### Rotate the database password

```bash
terraform taint module.rds.random_password.master
terraform apply -var-file=dev.tfvars
```

This regenerates the password, updates the secret, and modifies the instance.
ECS tasks pick up the new value on their next start — so a service restart is
required for existing tasks.

---

## Emergency procedures

**Suspected credential compromise**
1. Deactivate the IAM access key immediately.
2. Review CloudTrail for that principal.
3. Rotate the database password.
4. Review the OIDC role trust policy for unexpected subject patterns.

**Runaway cost**
1. `terraform destroy` the dev environment — NAT and RDS are the largest hourly
   charges.
2. Check for orphaned resources not managed by Terraform (unattached EIPs,
   old snapshots, forgotten load balancers).

**Complete environment rebuild**
Because everything is code, recovery is `terraform apply`. The exceptions are
stateful: the RDS data (restore from snapshot) and the Terraform state itself
(restore from S3 versioning).
