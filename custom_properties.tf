# Classification. The org defines the schema once; every managed repository
# carries a value for each required property. The criticality property is the
# repository's tier, and the tier selects its branch rules (locals.tf).
#
# GitHub's own "required" flag stays off: it would force a default value onto
# repositories this code doesn't manage. Terraform requires the values instead
# (variables.tf), for every repository it manages.
resource "github_organization_custom_properties" "this" {
  for_each = { for name, property in var.custom_properties : name => property if property.enabled }

  property_name      = each.key
  value_type         = each.value.value_type
  description        = each.value.description
  allowed_values     = each.value.value_type == "single_select" ? each.value.allowed_values : null
  required           = false
  values_editable_by = local.property_editors[each.value.editable_by]

  lifecycle {
    # Deleting a property wipes its value from every repository in the org,
    # including ones this code doesn't manage. To stop managing a property,
    # use a removed block (docs/controls.md); never let a plan delete it.
    prevent_destroy = true
  }
}

resource "github_repository_custom_property" "this" {
  for_each = local.repository_property_values

  # Both references make the order explicit: the repository and the property
  # exist before the value is set, and the value goes before the repository is
  # archived (an archived repository is read-only).
  repository     = module.repository[each.value.repository].name
  property_name  = github_organization_custom_properties.this[each.value.property].property_name
  property_type  = each.value.type
  property_value = [each.value.value]
}
