# Contributing

## Local setup

```bash
pip install --user pre-commit checkov
pre-commit install

make fmt      # terraform fmt -recursive
make lint     # tflint
make sec      # checkov
make test     # terraform test across all modules
make validate-all  # terraform validate in every directory, no AWS needed
```

## Workflow

1. Branch from `main` using a conventional prefix:
   `feat/`, `fix/`, `docs/`, `chore/`, `refactor/`, `test/`
2. Make the change. Run `make fmt lint test` before committing.
3. Open a pull request. CI runs format check, tflint, Checkov,
   `terraform test`, and `terraform plan` for all three environments.
4. **Read the plan posted to the PR before requesting review.** Look
   specifically for destroy and replace actions you did not intend.
5. Review the Infracost comment — a change that adds cost should say so in the
   PR description.
6. Merge to `main`. Applies are gated by GitHub Environments.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/):

```
feat(vpc): add interface endpoint for SSM
fix(ecs): correct health check grace period
docs(security): document the OIDC subject claim condition
chore(deps): bump aws provider to 6.12
```

## Rules

- Never commit state files, credentials, or tfvars containing secrets.
- Every variable and output needs a `description` — tflint enforces this.
- Environment differences belong in `.tfvars`, not in conditional logic.
- Child modules never contain a `provider` block.
- Architectural changes need an ADR entry in `docs/DECISIONS.md`.
- Never suppress a Checkov finding without a comment explaining the
  justification. An unexplained suppression is worse than the finding.
- Changes to `bootstrap/` affect every environment's state — treat them as
  high risk and explain the blast radius in the PR.
