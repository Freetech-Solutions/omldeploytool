terraform {
  required_version = ">= 1.10.0"

  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.0"
    }
  }

  # Spaces habla S3. bucket y endpoints van en el backend.hcl del tenant
  # (terraform init -backend-config=...). Las credenciales van en el entorno:
  # AWS_ACCESS_KEY_ID y AWS_SECRET_ACCESS_KEY, no VULTR_API_KEY.
  # La key es distinta a la de terraform/digitalocean: el mismo Space puede
  # guardar los dos states.
  backend "s3" {
    key    = "terraform/vultr/terraform.tfstate"
    region = "us-east-1"

    use_lockfile                = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    skip_region_validation      = true
  }
}
