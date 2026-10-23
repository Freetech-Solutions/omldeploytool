data "vultr_vpc" "oml" {
  filter {
    name   = "description"
    values = [var.vpc_description]
  }
}

data "vultr_os" "image" {
  count = var.snapshot_id == "" ? 1 : 0

  filter {
    name   = "name"
    values = [var.os_name]
  }
}

data "vultr_ssh_key" "admin" {
  for_each = toset(var.ssh_key_names)

  filter {
    name   = "name"
    values = [each.value]
  }
}
