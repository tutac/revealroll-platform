# The contract between this stack and Stage 02's Ansible inventory.
#
# Outputs are the only supported way for anything outside this stack to learn a value
# from it. The alternative -- reading terraform.tfstate, or copy-pasting the IP into
# inventory/staging.yml by hand -- is how an inventory quietly ends up pointing at a
# server that was rebuilt three months ago.

locals {
  # one() errors if there is ever more than one server node, which is the correct
  # failure for a single-control-plane k3s build. The variable validation catches it
  # first; this is the belt to that braces.
  server = one([for name, n in var.nodes : name if n.role == "server"])
}

output "instance_id" {
  description = "Contabo numeric instance ID of the server node. Needed to re-import if state is lost."
  value       = module.nodes[local.server].instance_id
}

output "hostname" {
  description = "Contabo-assigned hostname of the server node (e.g. vmi3503241)."
  value       = module.nodes[local.server].hostname
}

output "ipv4" {
  description = "Public IPv4 of the server node -- feeds ansible/inventory/staging.yml and the Namecheap *.stg A record."
  value       = module.nodes[local.server].ipv4
}

output "ipv6" {
  description = "Public IPv6 of the server node. Unused today; k3s and ingress are IPv4-only here."
  value       = module.nodes[local.server].ipv6
}

output "nodes" {
  description = "Every node, keyed by inventory name. Stage 03 generates the Ansible inventory from this."
  value = {
    for name, m in module.nodes : name => {
      id       = m.instance_id
      hostname = m.hostname
      ipv4     = m.ipv4
      role     = var.nodes[name].role
    }
  }
}
