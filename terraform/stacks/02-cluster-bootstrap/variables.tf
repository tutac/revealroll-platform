# Non-secret values live here as defaults, not in a gitignored .tfvars -- see decision 010.
# Credentials still come only from the environment (AWS_* for the R2 backend).

variable "kubeconfig_path" {
  description = "Kubeconfig written by scripts/fetch-kubeconfig.sh. Points at 127.0.0.1:6443; requires `make tunnel`."
  type        = string
  default     = "~/.kube/revealroll-staging.yaml"
}

variable "kube_context" {
  description = "Context name inside that kubeconfig. Set explicitly so this stack can never follow a stray current-context."
  type        = string
  default     = "revealroll-staging"
}

variable "base_domain" {
  description = "Staging base domain. Every bootstrap hostname is a label under this."
  type        = string
  default     = "stg.revealroll.com"
}

# ── chart versions ───────────────────────────────────────────────────────────────
# Pinned exactly, never a range. A floating chart version means `terraform apply` can
# change the cluster without the diff showing why -- the same argument as the image-tag
# rule in CLAUDE.md. Bumping one of these is a commit, reviewable on its own.

variable "ingress_nginx_chart_version" {
  description = "ingress-nginx chart version (app 1.15.1)."
  type        = string
  default     = "4.15.1"
}

variable "cert_manager_chart_version" {
  description = "cert-manager chart version."
  type        = string
  default     = "v1.21.1"
}

variable "sealed_secrets_chart_version" {
  description = "sealed-secrets chart version (app 0.38.4)."
  type        = string
  default     = "2.19.1"
}

variable "argocd_chart_version" {
  description = "argo-cd chart version (app v3.5.1)."
  type        = string
  default     = "10.3.3"
}

variable "acme_email" {
  description = "Let's Encrypt registration email. Not a secret -- it lives in the ACME account and receives expiry warnings."
  type        = string
  default     = "hasantutacdevops@gmail.com"

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.acme_email))
    error_message = "acme_email must be a real address; Let's Encrypt rejects registration otherwise."
  }
}

variable "acme_issuer" {
  description = "ClusterIssuer for bootstrap certificates. Start on staging; flip to prod only once a challenge has succeeded (task 04.8)."
  type        = string
  default     = "letsencrypt-staging"

  validation {
    condition     = contains(["letsencrypt-staging", "letsencrypt-prod"], var.acme_issuer)
    error_message = "acme_issuer must be letsencrypt-staging or letsencrypt-prod -- those are the only two ClusterIssuers this stack creates."
  }
}
