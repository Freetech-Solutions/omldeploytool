provider "vultr" {
  # null: el provider lee VULTR_API_KEY del entorno.
  api_key     = var.vultr_api_key != "" ? var.vultr_api_key : null
  rate_limit  = 100
  retry_limit = 3
}
