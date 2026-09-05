SHELL := /bin/bash
UID   := $(shell id -u)
GID   := $(shell id -g)

TF_DIRS := bootstrap \
           environments/dev environments/staging environments/prod \
           $(wildcard modules/*)

CHECKOV_VERSION := 3.3.16
CHECKOV := docker run --rm --user $(UID):$(GID) \
             -v "$(CURDIR)":/tf -w /tf \
             ghcr.io/bridgecrewio/checkov:$(CHECKOV_VERSION)

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: fmt
fmt: ## Format all Terraform files in place
	terraform fmt -recursive

.PHONY: fmt-check
fmt-check: ## Verify formatting (CI mode)
	terraform fmt -check -recursive -diff

.PHONY: validate
validate: ## Init without backend and validate every root and module
	@set -euo pipefail; \
	for dir in $(TF_DIRS); do \
	  echo "==> $$dir"; \
	  terraform -chdir=$$dir init -backend=false -input=false -no-color > /dev/null; \
	  terraform -chdir=$$dir validate -no-color; \
	done

.PHONY: lint
lint: ## Run tflint across the repository
	tflint --init --config="$(CURDIR)/.tflint.hcl"
	tflint --recursive --format compact --config="$(CURDIR)/.tflint.hcl"

.PHONY: scan
scan: ## Run Checkov against the committed baseline
	$(CHECKOV) --directory /tf --framework terraform \
	  --baseline /tf/.checkov.baseline --compact --quiet

.PHONY: scan-all
scan-all: ## Run Checkov with no baseline (shows every finding)
	$(CHECKOV) --directory /tf --framework terraform --compact --soft-fail

.PHONY: baseline
baseline: ## Regenerate .checkov.baseline from the current code
	$(CHECKOV) --directory /tf --framework terraform --create-baseline --soft-fail
	@echo "Baseline regenerated. Review the diff before committing."

.PHONY: ci
ci: fmt-check validate lint scan ## Run the full pipeline exactly as CI does

.PHONY: clean
clean: ## Remove local Terraform artefacts
	find . -type d -name ".terraform" -prune -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name ".terraform.lock.hcl" -delete
