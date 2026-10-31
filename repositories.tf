# Every repository is built from one module, so they all get the same
# protections and adding one is a few lines in platform.auto.tfvars.
module "repository" {
  source   = "./modules/repository"
  for_each = var.repositories

  name                            = each.key
  description                     = each.value.description
  visibility                      = each.value.visibility
  topics                          = each.value.topics
  has_issues                      = each.value.has_issues
  has_wiki                        = each.value.has_wiki
  has_projects                    = each.value.has_projects
  required_approving_review_count = each.value.required_approving_review_count
  required_status_checks          = each.value.required_status_checks

  team_access = {
    for team, permission in local.repository_team_access[each.key] :
    team => {
      team_id    = github_team.this[team].id
      permission = permission
    }
  }
}
