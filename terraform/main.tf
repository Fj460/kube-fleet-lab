locals {
  common_tags = distinct(concat(["k8s-fleet-lab"], var.tags))

  nodes = {
    fleet-hub = {
      size = "s-2vcpu-4gb"
    }
    member-1 = {
      size = "s-1vcpu-2gb"
    }
    member-2 = {
      size = "s-1vcpu-2gb"
    }
  }
}

resource "digitalocean_vpc" "lab" {
  name     = "${var.name_prefix}-vpc"
  region   = var.region
  ip_range = "10.20.0.0/20"
}

resource "digitalocean_droplet" "node" {
  for_each = local.nodes

  name     = "${var.name_prefix}-${each.key}"
  region   = var.region
  size     = each.value.size
  image    = var.image
  vpc_uuid = digitalocean_vpc.lab.id
  ssh_keys = var.ssh_key_ids
  tags     = local.common_tags

  monitoring = true

  lifecycle {
    create_before_destroy = false
  }
}

resource "digitalocean_firewall" "lab" {
  name        = "${var.name_prefix}-firewall"
  droplet_ids = [for node in digitalocean_droplet.node : node.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.admin_ip_cidrs
  }

  # Admin laptop can access each cluster API. Member agents can access the
  # hub API because they carry the k8s-fleet-lab tag.
  inbound_rule {
    protocol         = "tcp"
    port_range       = "6443"
    source_addresses = var.admin_ip_cidrs
  }

  inbound_rule {
    protocol    = "tcp"
    port_range  = "6443"
    source_tags = local.common_tags
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
