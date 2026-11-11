variable "do_token" {
  description = "DigitalOcean API token. Prefer TF_VAR_do_token in the shell."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "DigitalOcean region for all lab resources."
  type        = string
  default     = "nyc3"
}

variable "image" {
  description = "Ubuntu image slug."
  type        = string
  default     = "ubuntu-24-04-x64"
}

variable "ssh_key_ids" {
  description = "DigitalOcean SSH key IDs or fingerprints already uploaded to your account."
  type        = list(string)
}

variable "admin_ip_cidrs" {
  description = "Public IPv4 CIDRs allowed to SSH and access Kubernetes APIs."
  type        = list(string)

  validation {
    condition = (
      length(var.admin_ip_cidrs) > 0 &&
      alltrue([
        for cidr in var.admin_ip_cidrs :
        can(cidrnetmask(cidr))
      ])
    )

    error_message = "Every entry in admin_ip_cidrs must be a valid IPv4 CIDR, e.g. 203.0.113.10/32."
  }
}

variable "name_prefix" {
  description = "Prefix for lab resource names."
  type        = string
  default     = "k8s-fleet-lab"
}

variable "tags" {
  description = "Additional DigitalOcean tags applied to lab Droplets."
  type        = list(string)
  default     = []
}
