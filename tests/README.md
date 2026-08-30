# Infrastructure tests

Terraform's native test framework looks for `*.tftest.hcl` files in a
`tests/` directory **inside the module under test**, so the suites live at:

```
modules/vpc/tests/vpc.tftest.hcl
modules/rds/tests/rds.tftest.hcl
modules/ecs/tests/ecs.tftest.hcl
```

Run them all with `make test`, or individually:

```bash
cd modules/vpc && terraform init && terraform test
```

## Why `command = plan` and not `apply`

Every assertion here is a **structural invariant** — is the database private,
do tasks get public IPs, is storage encrypted. Those are all knowable from the
plan, so the tests run in seconds and cost nothing.

`command = apply` would create real AWS resources and is only justified when
you must assert on **runtime behaviour** that a plan cannot know: does the
application actually respond, can the ECS task really reach the database, does
failover work. That is Terratest territory, and it belongs in a scheduled
pipeline against a throwaway environment — not on every pull request.

## What these tests actually protect

They turn the security requirements into executable rules. If a future change
makes RDS publicly accessible, gives Fargate tasks public IPs, or removes
encryption, CI fails before the change can merge. That is the difference
between a documented policy and an enforced one.
