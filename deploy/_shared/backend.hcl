include "config" {
  path = "./config.hcl"
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket = include.config.locals.config.state_bucket
    key    = "constructor/terraform.tfstate"
    region = "auto"

    endpoints = {
      s3 = "https://${include.config.locals.config.cloudflare_account_id}.r2.cloudflarestorage.com"
    }

    access_key = include.config.locals.config.state_access_key
    secret_key = include.config.locals.config.state_secret_key

    # R2 doesn't behave like S3 in these areas; tell Terraform to skip checks
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_path_style              = true
    encrypt                     = false
  }
}
