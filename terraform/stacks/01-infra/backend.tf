terraform {
  backend "s3" {
    bucket = "revealroll-tfstate"
    key    = "01-infra/terraform.tfstate"
    region = "auto" # R2 has no regions; the AWS SDK requires the field anyway

    # NOTE the .eu. -- these buckets are in the EU jurisdiction, which has its own
    # endpoint host. The plain <account>.r2.cloudflarestorage.com returns AccessDenied.
    endpoints = {
      s3 = "https://75df4ff39c59aa632bcc37322e880646.eu.r2.cloudflarestorage.com"
    }

    # Path-style: https://endpoint/bucket/key, not https://bucket.endpoint/key.
    # Without this the SDK invents a virtual-host domain that does not resolve.
    use_path_style = true

    # R2 is not AWS. These four stop the SDK doing AWS-only things (IMDS lookups,
    # STS calls, region validation) that hang or fail against a non-AWS endpoint.
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true

    # R2 rejects the x-amz-checksum-* headers newer AWS SDKs send.
    # Without this, every state write fails with an opaque 400.
    skip_s3_checksum = true

    # S3-native locking via conditional writes (Terraform >= 1.10).
    # This is what DynamoDB would do on real AWS. R2 supports conditional writes.
    use_lockfile = true
  }
}