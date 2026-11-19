output "droplets" {
  description = "Infrastructure details indexed by logical cluster name."

  value = {
    for name, node in digitalocean_droplet.cluster : name => {
      public_ip  = node.ipv4_address
      private_ip = node.ipv4_address_private
      id         = node.id
      size       = node.size
      region     = node.region
    }
  }
}

output "cluster_public_ips" {
  description = "Public IPs indexed by logical cluster name."

  value = {
    for name, node in digitalocean_droplet.cluster :
    name => node.ipv4_address
  }
}