terraform {
  required_version = ">= 1.10"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
  }
}

# Both providers read the kubeconfig written by scripts/fetch-kubeconfig.sh, which points
# at 127.0.0.1:6443 -- so `make tunnel` MUST be running before plan or apply. Without it
# every operation fails with "connection refused" on localhost, which reads like a broken
# cluster and is actually a missing SSH session. That is the cost of decision 011, and
# this is the place it gets paid.
#
# config_context is set explicitly rather than relying on current-context: a provider that
# silently follows whatever context your shell last selected is a provider that will one
# day apply this stack to the wrong cluster.
provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kube_context
}

provider "helm" {
  # helm provider 3.x takes this as an attribute, not a nested block.
  kubernetes = {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kube_context
  }
}
