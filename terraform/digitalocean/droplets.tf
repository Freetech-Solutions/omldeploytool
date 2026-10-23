data "digitalocean_ssh_key" "admin" {
  for_each = toset(var.ssh_key_names)
  name     = each.value
}

resource "digitalocean_droplet" "node" {
  for_each = local.active_nodes

  # DigitalOcean solo acepta letras, números, puntos y guiones. El inventario Ansible sigue con _.
  name       = replace(each.key, "_", "-")
  region     = var.region
  size       = each.value.size
  image      = var.image
  vpc_uuid   = data.digitalocean_vpc.oml.id
  ssh_keys   = [for key in data.digitalocean_ssh_key.admin : key.id]
  user_data  = file(var.user_data_file)
  monitoring = true
  # Al pasar compute_enabled a false, apagar el servicio antes de borrar el disco.
  graceful_shutdown = true

  tags = concat(
    ["omnileads", "tenant:${var.tenant}"],
    [for role in each.value.roles : "role:${role}"],
  )

  # cloud-init corre solo en el primer boot. Un cambio del YAML no debe recrear do_data.
  lifecycle {
    ignore_changes = [user_data]
  }
}
