resource "contabo_instance" "this" {
  product_id   = var.product_id
  image_id     = var.image_id
  region       = var.region
  display_name = var.display_name
  ssh_keys     = var.ssh_keys

  # A dynamic block so a node with no add-ons emits no add_ons blocks at all,
  # rather than an empty one the provider would read as "cancel everything".
  dynamic "add_ons" {
    for_each = var.add_ons
    content {
      id       = add_ons.value.id
      quantity = add_ons.value.quantity
    }
  }
}
