output "droplets" {
  description = "Public and VPC-private addresses for each lab node."
  value = {
    for name, node in digitalocean_droplet.node : name => {
      public_ip  = node.ipv4_address
      private_ip = node.ipv4_address_private
      id         = node.id
      size       = node.size
    }
  }
}

output "hub_public_ip" {
  value = digitalocean_droplet.node["fleet-hub"].ipv4_address
}

output "member_public_ips" {
  value = {
    for name, node in digitalocean_droplet.node : name => node.ipv4_address
    if startswith(name, "member-")
  }
}
