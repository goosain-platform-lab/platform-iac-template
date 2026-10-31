resource "github_team" "this" {
  for_each = var.teams

  name        = each.key
  description = each.value.description
  privacy     = each.value.privacy
}

# Who may use the repository that holds this code. Terraform manages the access,
# not the repository itself: the control repo is bootstrapped by hand (see
# docs/setup.md) so this code can never delete or lock its own home.
resource "github_team_repository" "control_repository" {
  for_each = var.control_repository == null ? tomap({}) : var.control_repository.team_access

  team_id    = github_team.this[each.key].id
  repository = var.control_repository.name
  permission = local.api_permission[each.value]
}
