terraform {
  backend "s3" {
    bucket = "revealroll-tfstate"

    # A DIFFERENT key from 01-infra. Same bucket, separate state file: the two stacks have
    # different blast radii and different apply cadences, and sharing one state would mean
    # a bootstrap mistake can taint the record of the VPS itself.
    key    = "02-cluster-bootstrap/terraform.tfstate"
    region = "auto"

    # Every setting below is identical to 01-infra/backend.tf and identical for the same
    # reasons -- see the comments there before changing any of them. The short version:
    # R2 is S3-compatible but not S3, and each of these turns off an AWS-only behaviour
    # that otherwise hangs or fails.
    endpoints = {
      s3 = "https://75df4ff39c59aa632bcc37322e880646.eu.r2.cloudflarestorage.com"
    }

    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_lockfile                = true
  }
}
