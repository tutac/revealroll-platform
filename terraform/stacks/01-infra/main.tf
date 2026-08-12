module "nodes" {
  source   = "../../modules/contabo-instance"
  for_each = var.nodes

  product_id   = each.value.product_id
  image_id     = each.value.image_id
  region       = each.value.region
  display_name = each.value.display_name
  ssh_keys     = each.value.ssh_keys
  add_ons      = each.value.add_ons
}

# Stage 01.8: the instance used to be a bare contabo_instance.this in this stack.
# Moving it into a module changes its ADDRESS, and Terraform reads an address it no
# longer recognises as "destroy that, create this" -- which would rebuild the VPS.
#
# `moved` tells it the two addresses are the same object, so this is a state rename and
# the plan stays empty. Keep this block: it is what makes `git clone && terraform plan`
# work for anyone whose state predates the refactor. It costs nothing to leave in.
moved {
  from = contabo_instance.this
  to   = module.nodes["staging-1"].contabo_instance.this
}
