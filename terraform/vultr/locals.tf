locals {
  # keep = true sobrevive a compute_enabled = false (data y edge).
  active_nodes = {
    for name, node in var.nodes : name => node
    if var.compute_enabled || node.keep
  }

  # Vultr parte el CIDR en subnet + subnet_size. El guion del rango de
  # puertos pasa a dos puntos, que es lo que acepta la API.
  ssh_cidrs = {
    for cidr in var.ssh_allowed_cidrs : cidr => {
      ip_type     = strcontains(cidr, ":") ? "v6" : "v4"
      subnet      = split("/", cidr)[0]
      subnet_size = tonumber(split("/", cidr)[1])
    }
  }

  edge_rules = {
    for rule in flatten([
      for inbound in var.edge_inbound : [
        for cidr in inbound.sources : {
          key         = "${lower(inbound.protocol)}-${replace(inbound.port_range, "-", ":")}-${cidr}"
          protocol    = lower(inbound.protocol)
          port        = lower(inbound.protocol) == "icmp" ? null : replace(inbound.port_range, "-", ":")
          ip_type     = strcontains(cidr, ":") ? "v6" : "v4"
          subnet      = split("/", cidr)[0]
          subnet_size = tonumber(split("/", cidr)[1])
        }
      ]
    ]) : rule.key => rule
  }
}
