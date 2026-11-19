
locals {
  common_tags = distinct(concat(["k8s-fleet-lab"], var.tags))
}

resource "digitalocean_vpc" "cluster" {
  for_each = var.clusters

  name     = "k8s-${each.key}-vpc"
  region   = each.value.region
  ip_range = each.value.cidr
}

resource "digitalocean_droplet" "cluster" {
  for_each = var.clusters

  name     = "${var.name_prefix}-${each.key}"
  region   = each.value.region
  size     = each.value.size
  image    = var.image
  vpc_uuid = digitalocean_vpc.cluster[each.key].id
  ssh_keys = var.ssh_key_ids
  tags     = local.common_tags

  monitoring = true
}

resource "digitalocean_firewall" "cluster" {
  for_each = var.clusters

  name = "${var.name_prefix}-${each.key}-firewall"

  droplet_ids = [
    digitalocean_droplet.cluster[each.key].id
  ]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.admin_ip_cidrs
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "6443"
    source_addresses = var.admin_ip_cidrs
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
