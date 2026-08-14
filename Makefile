.DEFAULT_GOAL := help
SHELL := /bin/bash

# Which Terraform stack to act on: 01-infra (default) or 02-cluster-bootstrap
STACK      ?= 01-infra
TF          = terraform -chdir=terraform/stacks/$(STACK)

INVENTORY  ?= inventory/staging.yml
KUBECONFIG_PATH ?= $(HOME)/.kube/revealroll-staging.yaml
DOMAIN     ?= stg.revealroll.com

# Must match ansible_port / ansible_user in ansible/inventory/staging.yml.
SSH_PORT   ?= 22
SSH_USER   ?= deploy

## ───────────────────────────── help ─────────────────────────────

help: ## Show this help
	@echo ""
	@echo "  RevealRoll Platform — make targets"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  STACK=$(STACK)  (override: make tf-plan STACK=02-cluster-bootstrap)"
	@echo ""

## ─────────────────────────── terraform ──────────────────────────

tf-init: ## terraform init for $(STACK)
	$(TF) init

tf-plan: ## terraform plan for $(STACK)
	$(TF) plan

tf-apply: ## terraform apply for $(STACK)
	$(TF) apply

tf-output: ## Print the VPS IPv4 from stack 01-infra
	@terraform -chdir=terraform/stacks/01-infra output -raw ipv4; echo

tf-fmt: ## Format all Terraform
	terraform fmt -recursive

## ──────────────────────────── ansible ───────────────────────────

ansible-ping: ## Can we reach the host?
	cd ansible && ansible -i $(INVENTORY) all -m ping

ansible-site: ## Run the full site playbook
	cd ansible && ansible-playbook -i $(INVENTORY) site.yml

ansible-check: ## Dry-run the site playbook, showing file diffs
	cd ansible && ansible-playbook -i $(INVENTORY) site.yml --check --diff

ansible-verify: ## Run only the assertion playbook
	cd ansible && ansible-playbook -i $(INVENTORY) playbooks/99-verify.yml

idempotency: ## Prove Ansible is idempotent — the second run must report changed=0
	@cd ansible && ansible-playbook -i $(INVENTORY) site.yml >/dev/null
	@echo "── second run (must be changed=0) ──"
	@cd ansible && ansible-playbook -i $(INVENTORY) site.yml | tail -4

## ──────────────────────────── cluster ───────────────────────────

kubeconfig: ## Fetch the kubeconfig from the node
	@KUBECONFIG_PATH=$(KUBECONFIG_PATH) SSH_PORT=$(SSH_PORT) SSH_USER=$(SSH_USER) \
	  ./scripts/fetch-kubeconfig.sh

tunnel: ## Open the SSH tunnel to the kube-apiserver — 6443 is firewalled shut on purpose
	@HOST=$$(./scripts/fetch-kubeconfig.sh --print-host); \
	echo "→ 127.0.0.1:6443 → $$HOST:6443   (ctrl-c to close; leave this terminal open)"; \
	ssh -p $(SSH_PORT) -L 6443:127.0.0.1:6443 -N $(SSH_USER)@$$HOST

nodes: ## Show cluster nodes
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get nodes -o wide

broken: ## Show everything that is NOT running — the fastest triage command
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get pods -A --field-selector=status.phase!=Running || true
	@echo "── recent events ──"
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get events -A --sort-by=.lastTimestamp | tail -20

argocd-password: ## Print the Argo CD initial admin password
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl -n argocd get secret argocd-initial-admin-secret \
	  -o jsonpath='{.data.password}' | base64 -d; echo

apps: ## Argo CD application status
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get applications -n argocd

## ──────────────────────────── secrets ───────────────────────────

seal: ## Seal .env.staging into secrets/staging/ (never commits plaintext)
	./scripts/seal-env.sh .env.staging revealroll

backup-key: ## Back up the sealed-secrets private key — LOSE THIS AND ALL SECRETS DIE
	@KUBECONFIG=$(KUBECONFIG_PATH) kubectl get secret -n kube-system \
	  -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > $(HOME)/sealed-secrets-master.key
	@echo "✓ wrote $(HOME)/sealed-secrets-master.key — put it in your password manager, then delete it"

## ─────────────────────────── verify / lint ──────────────────────

smoke: ## Is the site up, on a healthy certificate?
	./scripts/smoke.sh https://$(DOMAIN)

cert: ## Show the TLS certificate issuer and expiry
	@echo | openssl s_client -connect $(DOMAIN):443 2>/dev/null \
	  | openssl x509 -noout -issuer -dates

ports: ## Confirm only SSH/80/443 are reachable from outside
	@nmap -Pn -p 22,80,443,6443,9100 $$(terraform -chdir=terraform/stacks/01-infra output -raw ipv4)

lint: ## Every pre-push check (the same ones CI runs)
	terraform fmt -recursive -check
	cd ansible && ansible-lint
	helm lint charts/revealroll
	helm template charts/revealroll -f charts/revealroll/values-staging.yaml \
	  | kubeconform -strict -summary -ignore-missing-schemas -
	gitleaks detect --no-git

.PHONY: help tf-init tf-plan tf-apply tf-output tf-fmt \
        ansible-ping ansible-site ansible-check ansible-verify idempotency \
        kubeconfig nodes broken argocd-password apps \
        seal backup-key smoke cert ports lint
