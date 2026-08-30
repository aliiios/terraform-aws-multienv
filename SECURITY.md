# Security Policy

## Reporting a vulnerability

Please report security issues privately using GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
rather than opening a public issue.

## Scope

This repository contains infrastructure-as-code definitions only. It contains
no credentials, no Terraform state, and no deployed endpoints.

The architecture's security model, threat scenarios and known gaps are
documented in [`docs/SECURITY.md`](docs/SECURITY.md).

## Secrets

Never commit passwords, API keys, private keys, AWS access keys, or connection
strings containing credentials.

If a secret is ever committed, **rotating it is mandatory**. Removing it from
git history is not sufficient — the value must be treated as compromised from
the moment it was pushed, because it may already have been cloned or indexed.

Automated controls in this repository:

- `.gitignore` blocks state files, `*.tfvars` by default, and key material
- `gitleaks` runs as a pre-commit hook
- `detect-private-key` runs as a pre-commit hook
- Checkov runs on every pull request
- CI authenticates to AWS via OIDC; no long-lived AWS keys exist in this repo
