# Contributing

## Prerequisites

| Tool | Version |
|---|---|
| Terraform | 1.11.4 |
| tflint | 0.58.0 |
| Docker | any recent version (used to run Checkov) |
| pre-commit | 3.x |

## Setup

```bash
git clone https://github.com/aliiios/terraform-aws-multienv.git
cd terraform-aws-multienv
pre-commit install
make help
```

## Before opening a pull request

```bash
make ci
```

This runs formatting, validation, linting and the security scan — the same four
checks CI runs, with the same commands. If `make ci` passes locally, CI will pass.

No AWS credentials are required for any of it. `terraform init` is invoked with
`-backend=false`, so nothing contacts a cloud provider.

## Commit convention

[Conventional Commits](https://www.conventionalcommits.org/):
`feat(vpc):`, `fix(bootstrap):`, `docs:`, `chore(ci):`, `test:`, `refactor:`.

## Security findings

`make scan-all` lists every Checkov finding, including baselined ones.
Fixing a baselined finding is always welcome — regenerate with `make baseline`
and commit the reduced file alongside the fix.
