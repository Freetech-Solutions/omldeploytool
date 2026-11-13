terraform {
  required_version = ">= 1.10.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }

  # Spaces habla S3. bucket y endpoints van en el backend.hcl del tenant
  # (terraform init -backend-config=...). Las credenciales van en el entorno:
  # AWS_ACCESS_KEY_ID y AWS_SECRET_ACCESS_KEY, no DIGITALOCEAN_TOKEN.
  backend "s3" {
    key    = "terraform/digitalocean/terraform.tfstate"
    region = "us-east-1"

    use_lockfile                = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    skip_region_validation      = true
  }
}
