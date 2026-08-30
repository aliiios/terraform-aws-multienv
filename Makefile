# Convenience wrapper. Usage:  make plan ENV=dev
ENV ?= dev
DIR  = environments/$(ENV)

.PHONY: help init fmt validate lint sec test plan apply destroy docs cost

help:
	@echo "make init|fmt|validate|lint|sec|test|plan|apply|destroy ENV=dev|staging|prod"

init:
	cd $(DIR) && terraform init -backend-config=backend.hcl

fmt:
	terraform fmt -recursive

validate:
	cd $(DIR) && terraform validate

# Validate every directory without touching any backend. Safe, offline, no AWS.
validate-all:
	@for d in bootstrap modules/vpc modules/ecs modules/rds modules/ecr \
	          environments/dev environments/staging environments/prod; do \
	  echo "== $$d"; \
	  ( cd $$d && terraform init -backend=false -input=false >/dev/null && terraform validate ) || exit 1; \
	done
	@echo "All configurations valid."


lint:
	tflint --recursive --config=$(PWD)/.tflint.hcl

sec:
	checkov -d . --quiet --compact --framework terraform

test:
	cd modules/vpc && terraform test
	cd modules/rds && terraform test
	cd modules/ecs && terraform test

plan:
	cd $(DIR) && terraform plan -var-file=$(ENV).tfvars -out=$(ENV).tfplan

apply:
	cd $(DIR) && terraform apply $(ENV).tfplan

destroy:
	cd $(DIR) && terraform destroy -var-file=$(ENV).tfvars

docs:
	terraform-docs markdown table --output-file README.md modules/vpc
	terraform-docs markdown table --output-file README.md modules/ecs
	terraform-docs markdown table --output-file README.md modules/rds
	terraform-docs markdown table --output-file README.md modules/ecr

cost:
	infracost breakdown --path environments/dev
