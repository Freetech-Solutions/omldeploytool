variable "digitalocean_token" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Token de API. Vacío: se usa la variable de entorno DIGITALOCEAN_TOKEN."
}

variable "region" {
  type        = string
  description = "Región de las droplets, la VPC y las IP reservadas (nyc3, ams3, fra1, ...)."
}

variable "image" {
  type        = string
  description = "Slug de distribución (debian-13-x64) o ID de un snapshot."
}

variable "tenant" {
  type        = string
  default     = "do_cluster"
  description = "Prefijo de nombres y tag de firewall. Alineado con ansible/instances/<tenant>."
}

variable "compute_enabled" {
  type        = bool
  default     = true
  description = "false destruye las droplets con keep = false. Las que tienen keep = true siguen creadas."
}

variable "vpc_name" {
  type        = string
  description = "Nombre de una VPC ya existente en la misma region. Las droplets se crean ahí; Terraform no crea ni borra la VPC."
}

variable "ssh_key_names" {
  type        = list(string)
  description = "Nombres de SSH keys ya cargadas en el panel de DigitalOcean. Se inyectan en root; cloud-init las copia a omladmin."
}

variable "ssh_allowed_cidrs" {
  type        = list(string)
  description = "Orígenes con SSH (tcp/22) hacia todas las droplets. No dejar 0.0.0.0/0."
}

variable "sip_allowed_cidrs" {
  type        = list(string)
  description = "Orígenes con SIP (udp/5060) hacia el edge. Va en el tfvars del tenant."
}

variable "user_data_file" {
  type        = string
  default     = "../../ansible/cloud_init_scripts/cloud_init_digital_ocean.yml"
  description = "cloud-init que crea omladmin. Ruta relativa a este directorio."
}

variable "nodes" {
  type = map(object({
    size  = string
    roles = list(string)
    keep  = bool
  }))
  description = "Droplets del tenant. roles son los grupos Ansible que corre esa máquina. keep = true no se destruye al apagar el cómputo."

  validation {
    condition     = alltrue([for node in var.nodes : length(node.roles) > 0])
    error_message = "Cada droplet necesita al menos un rol (grupo Ansible)."
  }
}
