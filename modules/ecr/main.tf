# =============================================================================
# ECR MODULE — private container registry
#
# IMMUTABLE TAGS: the single most important setting here.
#   With MUTABLE tags, `myapp:v1.2.0` can be overwritten by a different image.
#   That means the image running in production is not necessarily the image
#   you tested — and a rollback to "v1.2.0" may not restore what you think.
#   With IMMUTABLE tags, a tag permanently identifies one image digest.
#
# `latest` vs a digest:
#   latest        -> a mutable pointer; different every deploy; unreproducible.
#   sha256:<hex>  -> content-addressed; identical bytes, forever.
#   Production deployments should reference an immutable tag or, ideally,
#   the digest itself.
# =============================================================================

resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Encryption at rest for image layers.
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, { Name = var.name, Module = "ecr" })
}

# Lifecycle policy: registries grow without bound otherwise, and ECR storage
# is billed per GB-month. Rules are evaluated in priority order.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the most recent tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_tagged_images
        }
        action = { type = "expire" }
      },
    ]
  })
}
