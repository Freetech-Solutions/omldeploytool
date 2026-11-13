provider "digitalocean" {
  # null: el provider lee DIGITALOCEAN_TOKEN del entorno.
  token = var.digitalocean_token != "" ? var.digitalocean_token : null
}
