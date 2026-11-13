locals {
  ansible_hosts = {
    for name, droplet in digitalocean_droplet.node : name => {
      ansible_host = droplet.ipv4_address
      omni_ip_lan  = droplet.ipv4_address_private
      roles        = var.nodes[name].roles
    }
  }
}

output "compute_enabled" {
  value = var.compute_enabled
}

output "vpc_id" {
  value = data.digitalocean_vpc.oml.id
}

output "ansible_hosts" {
  description = "ansible_host es la IP pública de la droplet. omni_ip_lan es la privada de la VPC. Las dos cambian si la droplet se recrea."
  value       = local.ansible_hosts
}

output "ansible_limit_when_compute_returns" {
  description = "Grupos Ansible de las droplets con keep = false."
  value = join(":", distinct(flatten([
    for node in var.nodes : node.roles if !node.keep
  ])))
}
