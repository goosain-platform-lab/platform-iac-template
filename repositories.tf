# Every repository is built from one module, so they all get the same
# protections and adding one is a few lines in platform.auto.tfvars. Its branch
# rules come from its tier (locals.tf), not from per-repository settings.
module "repository" {
  source   = "./modules/repository"
  for_each = var.repositories

  name         = each.key
  description  = each.value.description
  visibility   = each.value.visibility
  topics       = each.value.topics
  has_issues   = each.value.has_issues
  has_wiki     = each.value.has_wiki
  has_projects = each.value.has_projects
  is_template  = each.value.is_template

  # Only used when the repository is created: it starts as a copy of the
  # template's files. Later changes to this setting are ignored.
  template = each.value.template == null ? null : {
    owner      = var.github_org
    repository = each.value.template
  }

  branch_rules = local.repository_branch_rules[each.key]

  team_access = {
    for team, permission in local.repository_team_access[each.key] :
    team => {
      team_id    = github_team.this[team].id
      permission = permission
    }
  }
}
