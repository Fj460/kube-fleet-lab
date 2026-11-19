variable "do_token" {
  description = "DigitalOcean API token. Prefer TF_VAR_do_token in the shell."
  type        = string
  sensitive   = true
}
variable "clusters" {
  description = "Configuration for each independent Kubernetes cluster."

  type = map(object({
    region = string
    cidr   = string
    size   = string
  }))
}

variable "name_prefix" {
  type    = string
  default = "k8s-fleet"
}

variable "image" {
  type = string
}

variable "ssh_key_ids" {
  type = list(string)
}

variable "admin_ip_cidrs" {
  type = list(string)
}

variable "tags" {
  type    = list(string)
  default = []
}