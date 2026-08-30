# ECR Module

Private container registry with immutable tags, scan-on-push, and a lifecycle
policy.

## Immutable tags

With `MUTABLE` tags, `app:v1.2.0` can be overwritten by different content. The
image running in production would then not provably be the image that was
tested, and rolling back to `v1.2.0` might not restore what you expect.

`IMMUTABLE` makes a tag permanently identify one image digest. Every change
requires a new tag — that friction is the mechanism working correctly.

## `latest` vs a digest

| Reference | Property |
|---|---|
| `app:latest` | mutable pointer, different every deploy, unreproducible |
| `app:v1.2.0` (immutable repo) | stable, human-readable, safe |
| `app@sha256:…` | content-addressed, identical bytes forever |

Production should reference an immutable tag or, ideally, a digest.

## Lifecycle policy

Untagged images are expired after a configurable number of days — they are
usually orphaned layers from overwritten manifests. Tagged images are capped at
a maximum count. ECR storage is billed per GB-month, so unbounded growth is a
slow cost leak.
