variable "vultr_api_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "API key. Vacia: se usa la variable de entorno VULTR_API_KEY. La IP de quien corre Terraform tiene que estar en la ACL de esa key."
}

variable "region" {
  type        = string
  description = "Region de las instancias (ewr, mia, sjp, ...). Tiene que ser la region de la VPC."
}

variable "os_name" {
  type        = string
  default     = "Debian 13 x64"
  description = "Nombre exacto en GET /v2/os. Se ignora si snapshot_id no esta vacio. packer/vultr/scripts/resolve-os-id.sh lista los Debian 13."
}

variable "snapshot_id" {
  type        = string
  default     = ""
  description = "Snapshot de packer/vultr, en la misma region. Vacio: se instala os_name."
}

variable "tenant" {
  type        = string
  default     = "do_cluster"
  description = "Prefijo de nombres. Alineado con ansible/instances/<tenant>."
}

variable "extra_tags" {
  type        = list(string)
  default     = []
  description = "Tags extra de Vultr, ademas de omnileads, tenant:<tenant> y role:<rol>."
}

variable "compute_enabled" {
  type        = bool
  default     = true
  description = "false destruye las instancias con keep = false. Las que tienen keep = true siguen creadas."
}

variable "vpc_description" {
  type        = string
  description = "Description de una VPC ya existente en la misma region. Las instancias se crean ahi; Terraform no crea ni borra la VPC."
}

variable "ssh_key_names" {
  type        = list(string)
  description = "Nombres de SSH keys ya cargadas en el panel de Vultr. Con user_scheme root quedan en root; cloud-init las copia a omladmin."
}

variable "ssh_allowed_cidrs" {
  type        = list(string)
  description = "Origenes con SSH (tcp/22) hacia todas las instancias. Va en el tfvars del tenant, no en este directorio."

  validation {
    condition     = length(var.ssh_allowed_cidrs) > 0 && alltrue([for cidr in var.ssh_allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "ssh_allowed_cidrs necesita al menos un CIDR, por ejemplo 203.0.113.10/32."
  }
}

variable "edge_inbound" {
  type = list(object({
    protocol   = string
    port_range = string
    sources    = list(string)
  }))
  default     = []
  description = "Entrada publica del edge, ademas de SSH. Los CIDR van en el tfvars del tenant. protocol: tcp, udp o icmp. port_range: 443 o 20000-30000."

  validation {
    condition = alltrue([
      for rule in var.edge_inbound : contains(["tcp", "udp", "icmp"], lower(rule.protocol))
    ])
    error_message = "edge_inbound.protocol tiene que ser tcp, udp o icmp."
  }

  validation {
    condition = alltrue([
      for rule in var.edge_inbound : (
        lower(rule.protocol) == "icmp" || can(regex("^[0-9]+([:-][0-9]+)?$", rule.port_range))
      )
    ])
    error_message = "edge_inbound.port_range tiene que ser un puerto o un rango, por ejemplo 443 o 20000-30000."
  }

  validation {
    condition = alltrue(flatten([
      for rule in var.edge_inbound : [
        for cidr in rule.sources : can(cidrhost(cidr, 0))
      ]
    ])) && alltrue([for rule in var.edge_inbound : length(rule.sources) > 0])
    error_message = "Cada regla de edge_inbound necesita al menos un CIDR en sources."
  }
}

variable "user_data_file" {
  type        = string
  default     = "../../ansible/cloud_init_scripts/cloud_init_vultr.yml"
  description = "cloud-init que crea omladmin. Ruta relativa al directorio desde el que se corre Terraform."
}

variable "nodes" {
  type = map(object({
    size  = string
    roles = list(string)
    keep  = bool
  }))
  description = "Instancias del tenant. size es el plan de Vultr (vc2-2c-4gb). roles son los grupos Ansible. keep = true no se destruye al apagar el computo."

  validation {
    condition     = alltrue([for node in var.nodes : length(node.roles) > 0])
    error_message = "Cada instancia necesita al menos un rol (grupo Ansible)."
  }
}
