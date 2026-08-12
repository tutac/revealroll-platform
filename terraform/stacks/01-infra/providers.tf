terraform {
  # 1.10+ is required for `use_lockfile` in the s3 backend (see backend.tf).
  # The course doc says >= 1.9; that predates S3-native state locking.
  required_version = ">= 1.10"

  required_providers {
    contabo = {
      source = "contabo/contabo"
      # Pinned: ~> 0.1.44 allows 0.1.45+ but never 0.2.0. A floating version is a
      # future 3 a.m. surprise -- the provider changes under you between applies.
      version = "~> 0.1.44"
    }
  }
}

# Deliberately empty. Credentials come from the environment only:
#   CNTB_OAUTH2_CLIENT_ID / CNTB_OAUTH2_CLIENT_SECRET / CNTB_OAUTH2_USER / CNTB_OAUTH2_PASS
# loaded by direnv from the gitignored .envrc. Never from .tfvars -- tfvars files get
# shared, copied, and eventually committed by someone.
provider "contabo" {}
