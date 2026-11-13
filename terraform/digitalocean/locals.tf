locals {
  # keep = true sobrevive a compute_enabled = false (data y edge en do_cluster).
  active_nodes = {
    for name, node in var.nodes : name => node
    if var.compute_enabled || node.keep
  }
}
