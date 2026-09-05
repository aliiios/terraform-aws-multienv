# Security Policy

## Scope

This repository contains infrastructure-as-code only. No production system is
deployed from it, and it holds no credentials, keys or account identifiers.

## Reporting a vulnerability

If you find a security issue in this code, please open a
[private security advisory](https://github.com/aliiios/terraform-aws-multienv/security/advisories/new)
rather than a public issue.

## Automated controls

Every push and pull request runs:

| Control | Tool | Enforcement |
|---|---|---|
| Static security analysis | Checkov 3.3.16 (pinned) | Blocking, against a committed baseline |
| Terraform linting | tflint + AWS ruleset | Blocking |
| Configuration validation | `terraform validate` | Blocking |
| Formatting | `terraform fmt -check` | Blocking |
| Action and image updates | Dependabot | Monthly pull requests |

Findings present when Checkov was adopted are recorded in `.checkov.baseline`
and are being reduced over time. Any **new** finding fails the build.

## Design decisions

Security choices made in this codebase — remote state encryption, network
isolation, least-privilege IAM, secret handling — are documented in
[`docs/`](./docs) and in the architecture decision records under
[`architecture/`](./architecture).
