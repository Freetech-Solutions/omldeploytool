# Tráfico entre nodos del tenant. Cubre Postgres, Redis, SIP interno y la app.
resource "digitalocean_firewall" "internal" {
  name = "${replace(var.tenant, "_", "-")}-internal"
  # El tag lo crea la droplet. El firewall no puede crearse en paralelo: la API
  # responde "tag does not exist" si el tag todavía no está en la cuenta.
  tags       = ["tenant:${var.tenant}"]
  depends_on = [digitalocean_droplet.node]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_allowed_cidrs
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "1-65535"
    source_addresses = [data.digitalocean_vpc.oml.ip_range]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "1-65535"
    source_addresses = [data.digitalocean_vpc.oml.ip_range]
  }

  inbound_rule {
    protocol         = "icmp"
    source_addresses = [data.digitalocean_vpc.oml.ip_range]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# HTTPS público solo en el borde. HAProxy termina TLS ahí.
resource "digitalocean_firewall" "edge" {
  name       = "${replace(var.tenant, "_", "-")}-edge"
  tags       = ["role:edge"]
  depends_on = [digitalocean_droplet.node]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "5060"
    source_addresses = var.sip_allowed_cidrs
  }

  # Google Telephony Platform: SIP over TLS return path (REFER/BYE) to Kamailio.
  # Signaling range documented by Google: 74.125.88.128/25, TCP 5672 outbound.
  inbound_rule {
    protocol         = "tcp"
    port_range       = "5061"
    source_addresses = ["74.125.88.128/25"]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "20000-30000"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
