# RDS Module

Managed PostgreSQL in the private data tier, with generated credentials stored
in Secrets Manager.

## Security model

- `publicly_accessible = false` — no public IP is ever assigned
- deployed into subnets with no route to NAT or the Internet Gateway
- `storage_encrypted = true` — cannot be enabled later without a
  snapshot/copy/restore cycle, so it is on from the first apply
- the security group ships with **no ingress rules**; the caller adds exactly
  one rule referencing the application tier's security group

## Why the ingress rule is not in this module

RDS would need the ECS security group ID, while the ECS module needs the
Secrets Manager ARN produced here. That is a circular module dependency
Terraform cannot resolve. The environment root module already depends on both,
so the cross-cutting rule is declared there. See `environments/*/main.tf`.

## Credentials

```
random_password → Secrets Manager secret → ECS task definition `secrets` block
```

The password never appears in tfvars, Git, or the task definition. It **is**
written to Terraform state, which is why the state bucket is KMS-encrypted,
versioned and public-access-blocked.

The secret value is a separate resource from the secret itself, because a
secret can hold many versions — which is what makes rotation possible without
changing the ARN that consumers reference.

## Enhanced Monitoring vs standard metrics

Standard CloudWatch RDS metrics are collected from the **hypervisor** at
60-second granularity. Enhanced Monitoring runs an agent **inside the database
host** and reports OS-level metrics — per-process CPU, memory, disk I/O — at up
to one-second granularity. Only the latter can tell you which process is
consuming resources.

## Production settings

| Setting | Dev | Production |
|---|---|---|
| `multi_az` | false | **true** |
| `backup_retention_period` | 1 | **30** |
| `deletion_protection` | false | **true** |
| `skip_final_snapshot` | true | **false** |
| `monitoring_interval` | 0 | **30** |
| `apply_immediately` | true | **false** (wait for the maintenance window) |
