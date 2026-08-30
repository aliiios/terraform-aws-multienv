# Application

A deliberately minimal container. Build and push it to ECR:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=eu-west-3
REPO=tf-aws-multienv-dev
TAG=v1.0.0

# 1. Authenticate podman/docker against ECR (token is valid 12 hours)
aws ecr get-login-password --region $REGION \
  | podman login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# 2. Build
podman build -t $REPO:$TAG ./app

# 3. Tag with the full registry path
podman tag $REPO:$TAG $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:$TAG

# 4. Push
podman push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:$TAG
```

Then set `container_image` in `environments/dev/dev.tfvars` to the pushed
reference and re-apply. Because the repository uses **immutable tags**, you
must bump the tag for every change — pushing `v1.0.0` twice is rejected.
That is the point: a tag permanently identifies one image.
