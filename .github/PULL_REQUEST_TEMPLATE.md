## What changed

<!-- One or two sentences. Link the issue if there is one. -->

## Why

<!-- The problem this solves. Not a restatement of the diff. -->

## Environments affected

- [ ] dev
- [ ] staging
- [ ] prod
- [ ] modules only (affects all environments)

## Checklist

- [ ] `terraform fmt -recursive` run
- [ ] `terraform validate` passes in every affected directory
- [ ] `terraform test` passes
- [ ] Plan reviewed in the CI comment — **no unexpected destroy or replace actions**
- [ ] Infracost delta reviewed and acceptable
- [ ] No secrets in code, tfvars, or plan output
- [ ] `docs/DECISIONS.md` updated if this changes an architectural decision
- [ ] Module README updated if inputs or outputs changed

## Risk and rollback

<!--
What breaks if this is wrong?
How would you roll it back?
Does it touch stateful resources (RDS, S3) where rollback is not just a revert?
-->
