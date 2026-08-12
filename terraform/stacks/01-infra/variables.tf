# Node definitions live here, with committed defaults, on purpose.
#
# None of these values are secret -- they are a product SKU, an image UUID, and a role.
# Putting them in a gitignored *.tfvars would mean a fresh clone of this repo cannot plan
# the stack, and "what is running in staging?" would no longer be answerable by reading
# Git. Secrets stay where they belong: CNTB_OAUTH2_* / AWS_* in the gitignored .envrc.

variable "nodes" {
  description = "Cluster nodes, keyed by inventory name. Adding a worker is one more entry."

  type = map(object({
    role         = string           # "server" | "agent" -- consumed by the Ansible inventory
    product_id   = string           #
    image_id     = string           # CHANGING THIS REINSTALLS THE MACHINE
    region       = optional(string) # null for existing nodes; set for new ones
    display_name = optional(string) # null leaves Contabo's own name
    ssh_keys     = optional(list(string), [])
    add_ons = optional(list(object({
      id       = string
      quantity = number
    })), [])
  }))

  validation {
    condition     = alltrue([for n in var.nodes : contains(["server", "agent"], n.role)])
    error_message = "Each node's role must be exactly \"server\" or \"agent\"."
  }

  validation {
    condition     = length([for n in var.nodes : n if n.role == "server"]) == 1
    error_message = "Exactly one node must have role = \"server\" -- k3s needs one control plane here."
  }

  default = {
    # The VPS bought by hand in the Contabo panel and imported in Stage 01.4.
    # region is intentionally omitted: see the module's variables.tf for why.
    "staging-1" = {
      role       = "server"
      product_id = "V153"
      image_id   = "d64d5c6c-9dda-4e38-8174-0ee282474d8a"
      add_ons    = [{ id = "1501", quantity = 1 }]
    }

    # Adding a worker later is exactly this, and nothing else:
    # "staging-2" = {
    #   role       = "agent"
    #   product_id = "V153"
    #   image_id   = "d64d5c6c-9dda-4e38-8174-0ee282474d8a"
    #   region     = "EU"          # required for a node that does not exist yet
    #   ssh_keys   = var.ssh_key_ids
    # }
  }
}

variable "ssh_key_ids" {
  description = "Contabo SSH key IDs to install on NEW instances. Empty today -- staging-1 predates any."
  type        = list(string)
  default     = []
}
