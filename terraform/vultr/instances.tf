resource "vultr_instance" "node" {
  for_each = local.active_nodes

  # El hostname de Vultr es minusculas, numeros y guiones. El inventario Ansible sigue con _.
  label       = lower(replace(each.key, "_", "-"))
  hostname    = lower(replace(each.key, "_", "-"))
  region      = var.region
  plan        = each.value.size
  os_id       = var.snapshot_id == "" ? data.vultr_os.image[0].id : null
  snapshot_id = var.snapshot_id != "" ? var.snapshot_id : null

  vpc_ids           = [data.vultr_vpc.oml.id]
  ssh_key_ids       = [for key in data.vultr_ssh_key.admin : key.id]
  user_data         = file(var.user_data_file)
  user_scheme       = "root"
  activation_email  = false
  enable_ipv6       = false
  firewall_group_id = contains(each.value.roles, "edge") ? vultr_firewall_group.edge.id : vultr_firewall_group.ssh.id

  tags = concat(
    ["omnileads", "tenant:${var.tenant}"],
    var.extra_tags,
    [for role in each.value.roles : "role:${role}"],
  )

  # cloud-init corre solo en el primer boot. Un cambio del YAML no recrea la instancia.
  lifecycle {
    ignore_changes = [user_data]

    precondition {
      condition     = lower(data.vultr_vpc.oml.region) == lower(var.region)
      error_message = "region tiene que coincidir con la region de la VPC (${data.vultr_vpc.oml.region})."
    }
  }
}
