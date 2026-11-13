# Una instancia acepta un solo firewall group. El de edge incluye SSH.
# Vultr filtra solo la entrada publica: la VPC y el trafico de salida no pasan
# por estas reglas. Sin group, la entrada publica queda abierta.
resource "vultr_firewall_group" "ssh" {
  description = "${replace(var.tenant, "_", "-")}-ssh"
}

resource "vultr_firewall_group" "edge" {
  description = "${replace(var.tenant, "_", "-")}-edge"
}

resource "vultr_firewall_rule" "ssh" {
  for_each = local.ssh_cidrs

  firewall_group_id = vultr_firewall_group.ssh.id
  protocol          = "tcp"
  ip_type           = each.value.ip_type
  subnet            = each.value.subnet
  subnet_size       = each.value.subnet_size
  port              = "22"
  notes             = "ssh"
}

resource "vultr_firewall_rule" "edge_ssh" {
  for_each = local.ssh_cidrs

  firewall_group_id = vultr_firewall_group.edge.id
  protocol          = "tcp"
  ip_type           = each.value.ip_type
  subnet            = each.value.subnet
  subnet_size       = each.value.subnet_size
  port              = "22"
  notes             = "ssh"
}

resource "vultr_firewall_rule" "edge" {
  for_each = local.edge_rules

  firewall_group_id = vultr_firewall_group.edge.id
  protocol          = each.value.protocol
  ip_type           = each.value.ip_type
  subnet            = each.value.subnet
  subnet_size       = each.value.subnet_size
  port              = each.value.port
  notes             = "edge"
}
