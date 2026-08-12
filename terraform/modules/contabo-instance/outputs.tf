output "instance_id" {
  description = "Contabo numeric instance ID. Needed to re-import if state is ever lost."
  value       = contabo_instance.this.id
}

output "hostname" {
  description = "Contabo-assigned hostname (e.g. vmi3503241). Read-only."
  value       = contabo_instance.this.name
}

# one() rather than [0]: it returns null on an empty list and errors loudly on more than
# one, instead of the cryptic index error [0] gives when an IP hasn't been assigned yet.
output "ipv4" {
  description = "Public IPv4."
  value       = one(one(contabo_instance.this.ip_config).v4).ip
}

output "ipv6" {
  description = "Public IPv6."
  value       = one(one(contabo_instance.this.ip_config).v6).ip
}
