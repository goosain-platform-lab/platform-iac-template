locals {
  # The GitHub UI says Read and Write; the API says pull and push. Config uses
  # the words you see in the UI, and this is the only place they're translated.
  api_permission = {
    read     = "pull"
    triage   = "triage"
    write    = "push"
    maintain = "maintain"
    admin    = "admin"
  }

  # Effective team access per repository: the org-wide default, overridden per
  # repository. A role of "none" removes a default grant from that repository.
  repository_team_access = {
    for repo, settings in var.repositories : repo => {
      for team, role in merge(var.default_team_access, settings.team_access) :
      team => local.api_permission[role]
      if role != "none"
    }
  }
}
