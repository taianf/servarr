# Makefile — convenience wrappers around bin/ scripts and helmfile.
# The underlying tools (sops, uv, helmfile, kubectl, helm) need to
# be on PATH; install with `make setup` (or via home.packages.nix
# in the dotfiles repo for reproducible installs).
#
# Run `make` or `make help` to list targets.

.DEFAULT_GOAL := help
NAMESPACE   ?= servarr
APP         ?=     # override: make restart APP=sonarr
JOB         ?=     # override: make apply-job JOB=prowlarr-applications

.PHONY: help
help: ## Show this help (default target)
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ---- Setup ----

.PHONY: setup check-prereqs
setup check-prereqs: ## Verify prereqs are on PATH (prints what's missing)
	@missing=0; \
	for tool in sops helmfile kubectl helm uv make; do \
	  if command -v $$tool >/dev/null 2>&1; then \
	    printf "  \033[32m✓\033[0m  %s\n" $$tool; \
	  else \
	    printf "  \033[31m✗\033[0m  %s (missing)\n" $$tool; \
	    missing=1; \
	  fi; \
	done; \
	if [ $$missing -ne 0 ]; then \
	  echo ""; \
	  echo "Add the missing tools to home/packages.nix in the dotfiles repo"; \
	  echo "(e.g. pkgs.sops, pkgs.kubectl, pkgs.uv, pkgs.gnumake) and run nixup."; \
	  echo "Helmfile is on PATH as 'helmfile' from pkgs.helmfile."; \
	  exit 1; \
	fi

# ---- Secrets ----

.PHONY: edit-secrets secrets render-secrets
edit-secrets: ## Open secrets.enc.yaml in $$EDITOR (sops decrypts, re-encrypts on save)
	sops secrets.enc.yaml

secrets: render-secrets ## Alias for `render-secrets`
render-secrets: ## Decrypt secrets.enc.yaml → secrets.dec.yaml + k8s Secret manifest
	./bin/render-secrets

# ---- Bring-up / tear-down ----

.PHONY: deploy start stop restart
deploy: ## End-to-end bring-up: secrets + manifests + helmfile + wiring Jobs
	./bin/deploy

start: deploy ## Alias for `deploy`

stop: ## Tear down all chart releases (data in /data is preserved)
	helmfile destroy

restart: ## Rollout-restart one Deployment (APP=sonarr)
	kubectl -n $(NAMESPACE) rollout restart deploy/$(APP)

# ---- Helmfile ----

.PHONY: apply diff build
apply: ## Apply all chart releases
	helmfile apply

diff: ## Show what helmfile would change
	helmfile diff

build: ## Render chart templates to stdout (no apply)
	helmfile build

# ---- Wiring Jobs ----

.PHONY: apply-jobs apply-job
apply-jobs: ## Re-run all wiring Jobs (idempotent)
	./bin/apply-jobs

apply-job: ## Re-run one Job (JOB=name, substring match)
	./bin/apply-jobs $(JOB)

# ---- Observability ----

.PHONY: status logs pods
status: ## Quick stack overview
	./bin/status

logs: ## Tail logs from every pod in the namespace
	kubectl -n $(NAMESPACE) logs -l app.kubernetes.io/part-of=servarr --tail=100 -f

pods: ## List pods in the namespace
	kubectl -n $(NAMESPACE) get pods

# ---- Dev workflow ----

.PHONY: lint format validate
lint: ## Run prek + yamllint (CI parity)
	prek run --all-files
	yamllint --config-file .yamllint .

format: ## Auto-fix via prek (prettier, end-of-file, etc.)
	prek run --all-files

validate: build ## Render charts to validate templates (alias for `make build`)

# ---- Cleanup ----

.PHONY: clean nuke
clean: ## Delete the servarr namespace + rendered secrets (data in /data preserved)
	kubectl delete namespace $(NAMESPACE) --ignore-not-found
	rm -f secrets.dec.yaml manifests/30-secrets.yaml

nuke: clean stop ## clean + helmfile destroy (full teardown)
