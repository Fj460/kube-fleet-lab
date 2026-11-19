# Droplets
moved {
  from = digitalocean_droplet.cluster["ams"]
  to   = digitalocean_droplet.cluster["fleet-hub"]
}

moved {
  from = digitalocean_droplet.cluster["nyc"]
  to   = digitalocean_droplet.cluster["member-1"]
}

moved {
  from = digitalocean_droplet.cluster["sgp"]
  to   = digitalocean_droplet.cluster["member-2"]
}

# VPCs
moved {
  from = digitalocean_vpc.cluster["ams"]
  to   = digitalocean_vpc.cluster["fleet-hub"]
}

moved {
  from = digitalocean_vpc.cluster["nyc"]
  to   = digitalocean_vpc.cluster["member-1"]
}

moved {
  from = digitalocean_vpc.cluster["sgp"]
  to   = digitalocean_vpc.cluster["member-2"]
}

# Firewalls
moved {
  from = digitalocean_firewall.cluster["ams"]
  to   = digitalocean_firewall.cluster["fleet-hub"]
}

moved {
  from = digitalocean_firewall.cluster["nyc"]
  to   = digitalocean_firewall.cluster["member-1"]
}

moved {
  from = digitalocean_firewall.cluster["sgp"]
  to   = digitalocean_firewall.cluster["member-2"]
}