locals {
  ansible_hosts = {
    for name, instance in vultr_instance.node : name => {
      ansible_host = instance.main_ip
      omni_ip_lan  = instance.internal_ip
      roles        = var.nodes[name].roles
    }
  }
}

output "compute_enabled" {
  value = var.compute_enabled
}

output "vpc_id" {
  value = data.vultr_vpc.oml.id
}

output "ansible_hosts" {
  description = "ansible_host es la IP publica. omni_ip_lan es la privada de la VPC. Las dos cambian si la instancia se recrea."
  value       = local.ansible_hosts
}

output "ansible_limit_when_compute_returns" {
  description = "Grupos Ansible de las instancias con keep = false."
  value = join(":", distinct(flatten([
    for node in var.nodes : node.roles if !node.keep
  ])))
}
