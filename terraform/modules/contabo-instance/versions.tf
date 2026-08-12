terraform {
  required_providers {
    contabo = {
      # Source only, no version constraint. A module that pins its own version can
      # deadlock against the root module's pin; the root (stacks/*/providers.tf) is
      # the single place a version is chosen. Without this block Terraform infers
      # hashicorp/contabo from the local name and fails to find it.
      source = "contabo/contabo"
    }
  }
}
