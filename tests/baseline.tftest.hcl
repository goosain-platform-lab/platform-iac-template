# Policy checks that must pass in EVERY environment. CI runs them once per
# environment, against the real config:
#   terraform test -var-file=environments/sandbox.tfvars
#   terraform test -var-file=environments/prod.tfvars
# The GitHub provider is mocked: no credentials, and nothing touches GitHub.

mock_provider "github" {}

variables {
  billing_email               = "platform-owner@lab.test"
  adopt_organization_settings = false # mocked providers cannot import
}

run "baseline_policy" {
  command = plan

  # --- Organization -------------------------------------------------------

  assert {
    condition = alltrue([
      !github_organization_settings.this.members_can_create_repositories,
      !github_organization_settings.this.members_can_create_public_repositories,
      !github_organization_settings.this.members_can_create_private_repositories,
    ])
    error_message = "Members must not create repositories by hand; every repository goes through this code."
  }

  assert {
    condition     = contains(["none", "read"], github_organization_settings.this.default_repository_permission)
    error_message = "The base permission must not grant write or admin to every member."
  }

  # --- Actions -------------------------------------------------------------

  assert {
    condition     = github_actions_organization_permissions.this.allowed_actions == "selected" && github_actions_organization_permissions.this.sha_pinning_required
    error_message = "Only selected actions may run, and they must be pinned to a full commit SHA."
  }

  assert {
    condition     = github_actions_organization_workflow_permissions.this.default_workflow_permissions == "read" && !github_actions_organization_workflow_permissions.this.can_approve_pull_request_reviews
    error_message = "GITHUB_TOKEN must default to read-only, and Actions must not approve pull requests."
  }

  # --- Repositories --------------------------------------------------------

  assert {
    condition     = length(module.repository) == length(var.repositories)
    error_message = "Every entry in var.repositories must produce a managed repository."
  }

  assert {
    condition     = alltrue([for repo in module.repository : repo.protection.archive_on_destroy])
    error_message = "Repositories must be archived, never deleted, when removed from config."
  }

  assert {
    condition     = alltrue([for repo in module.repository : repo.protection.ruleset == "default-branch-protection"])
    error_message = "Every repository's default branch must be protected by the standard ruleset."
  }

  assert {
    condition     = alltrue([for repo in module.repository : join(",", repo.protection.allowed_merge_methods) == "squash"])
    error_message = "Pull requests must be squash-merged."
  }

  assert {
    condition     = alltrue([for repo in module.repository : join(",", repo.protection.bypass) == "OrganizationAdmin via pull_request"])
    error_message = "Only org owners may bypass the ruleset, and only through a pull request."
  }

  assert {
    condition     = alltrue([for name, repo in module.repository : repo.protection.secret_scanning if var.repositories[name].visibility == "public"])
    error_message = "Public repositories must have secret scanning and push protection managed in code."
  }

  assert {
    condition     = alltrue([for repo in module.repository : repo.protection.dependabot_alerts && repo.protection.dependabot_updates])
    error_message = "Dependabot alerts and security updates must be on for every repository."
  }

  # --- Access --------------------------------------------------------------

  assert {
    condition     = alltrue(flatten([for repo in module.repository : [for permission in values(repo.team_access) : permission != "admin"]]))
    error_message = "No team may hold standing admin on a managed repository. Change this test only with an approved exception."
  }

  assert {
    condition = alltrue([
      for name, repo in module.repository : jsonencode(repo.team_access) == jsonencode({
        for team, role in merge(var.default_team_access, var.repositories[name].team_access) :
        team => lookup({ read = "pull", triage = "triage", write = "push", maintain = "maintain", admin = "admin" }, role)
        if role != "none"
      })
    ])
    error_message = "Each repository's team access must equal the default access merged with its own overrides."
  }

  assert {
    condition     = length(github_team_repository.control_repository) == length(try(var.control_repository.team_access, {}))
    error_message = "Access to the control repository must match var.control_repository exactly."
  }
}
