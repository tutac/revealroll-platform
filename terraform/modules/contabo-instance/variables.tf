# Deliberately two-nodes-worth of flexibility, not an internal platform product.
# Every variable here exists because a second (agent) node would need it.

variable "product_id" {
  description = "Contabo product, e.g. V153 = Cloud VPS 4 (4 vCPU / 8 GB / 100 GB SSD)."
  type        = string
}

variable "image_id" {
  description = "OS image UUID. CHANGING THIS REINSTALLS THE MACHINE."
  type        = string
}

variable "region" {
  description = <<-EOT
    Contabo region, e.g. "EU". Leave null for instances that already exist: this provider
    never reads region back on refresh, so setting it on an imported node plans as an
    update-in-place -- a pointless API write against a live VPS. Set it for NEW nodes,
    where it decides where the machine is actually built.
  EOT
  type        = string
  default     = null
}

variable "display_name" {
  description = "Panel label. Null leaves whatever Contabo assigned (e.g. vmi3503241)."
  type        = string
  default     = null
}

variable "ssh_keys" {
  description = "Contabo SSH key IDs to install at creation. Ignored for already-built nodes."
  type        = list(string)
  default     = []
}

variable "add_ons" {
  description = "Purchased add-ons already attached to the instance. Omitting one cancels it."
  type = list(object({
    id       = string
    quantity = number
  }))
  default = []
}
