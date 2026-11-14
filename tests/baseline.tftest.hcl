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
    condition     = github_organization_settings.this.default_repository_permission == "none"
    error_message = "The base permission must be none: access comes only from team grants."
  }

  assert {
    condition     = github_organization_settings.this.web_commit_signoff_required
    error_message = "Commits made in the web editor must carry the author's sign-off."
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

  # --- Classification ------------------------------------------------------

  assert {
    condition     = github_organization_custom_properties.this["criticality"].values_editable_by == "org_actors"
    error_message = "Only the org may set a repository's tier; otherwise a repository admin could lower their own branch rules."
  }

  assert {
    condition     = alltrue([for property in github_organization_custom_properties.this : !property.required])
    error_message = "GitHub's own required flag must stay off: it would force a default value onto repositories this code doesn't manage."
  }

  assert {
    condition = alltrue(flatten([
      for repo in keys(var.repositories) : [
        for property, definition in var.custom_properties :
        contains(keys(github_repository_custom_property.this), "${repo}/${property}")
        if definition.enabled && definition.required
      ]
    ]))
    error_message = "Every managed repository must be given a value for every required property."
  }

  assert {
    condition = alltrue([
      for name, property in var.custom_properties :
      !contains(keys(github_organization_custom_properties.this), name) &&
      length([for key, value in github_repository_custom_property.this : key if value.property_name == name]) == 0
      if !property.enabled
    ])
    error_message = "A switched-off property must never reach GitHub, neither its definition nor its values."
  }

  # --- Tiers ---------------------------------------------------------------

  assert {
    condition = alltrue([
      for tier in ["tier-1", "tier-2", "tier-3"] :
      var.tier_policies[tier].protected && var.tier_policies[tier].require_code_owner_review && var.tier_policies[tier].required_approving_review_count >= 1
    ])
    error_message = "Tiers 1 to 3 must be protected, with at least one approval and a code owner review."
  }

  assert {
    condition = alltrue([
      for pair in [["tier-1", "tier-2"], ["tier-2", "tier-3"]] : (
        var.tier_policies[pair[0]].required_approving_review_count >= var.tier_policies[pair[1]].required_approving_review_count &&
        (var.tier_policies[pair[0]].dismiss_stale_reviews_on_push || !var.tier_policies[pair[1]].dismiss_stale_reviews_on_push) &&
        (var.tier_policies[pair[0]].required_review_thread_resolution || !var.tier_policies[pair[1]].required_review_thread_resolution) &&
        (var.tier_policies[pair[0]].required_linear_history || !var.tier_policies[pair[1]].required_linear_history) &&
        (var.tier_policies[pair[0]].required_signatures || !var.tier_policies[pair[1]].required_signatures) &&
        (var.tier_policies[pair[0]].require_last_push_approval || !var.tier_policies[pair[1]].require_last_push_approval) &&
        length(setsubtract(var.tier_policies[pair[1]].required_status_checks, var.tier_policies[pair[0]].required_status_checks)) == 0
      )
    ])
    error_message = "A more critical tier must never have weaker rules than a less critical one."
  }

  assert {
    condition     = alltrue([for tier in ["tier-1", "tier-2"] : length(var.tier_policies[tier].required_status_checks) > 0])
    error_message = "Tier-1 and tier-2 changes must pass a required check before they merge."
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
    condition = alltrue([
      for name, repo in module.repository :
      (repo.protection.ruleset != null) == var.tier_policies[local.repository_tier[name]].protected
    ])
    error_message = "A repository must have a default-branch ruleset exactly when its tier is protected."
  }

  assert {
    condition = alltrue([
      for name, repo in module.repository : (
        repo.protection.ruleset.name == "default-branch-protection" &&
        repo.protection.ruleset.enforcement == var.repositories[name].ruleset_enforcement &&
        repo.protection.ruleset.no_deletion_or_force_push &&
        repo.protection.ruleset.required_approvals >= var.tier_policies[local.repository_tier[name]].required_approving_review_count &&
        repo.protection.ruleset.code_owner_review == var.tier_policies[local.repository_tier[name]].require_code_owner_review &&
        repo.protection.ruleset.dismiss_stale_reviews == var.tier_policies[local.repository_tier[name]].dismiss_stale_reviews_on_push &&
        repo.protection.ruleset.conversations_resolved == var.tier_policies[local.repository_tier[name]].required_review_thread_resolution &&
        repo.protection.ruleset.linear_history == var.tier_policies[local.repository_tier[name]].required_linear_history &&
        repo.protection.ruleset.signed_commits == var.tier_policies[local.repository_tier[name]].required_signatures &&
        length(setsubtract(var.tier_policies[local.repository_tier[name]].required_status_checks, repo.protection.ruleset.required_status_checks)) == 0
      )
      if repo.protection.ruleset != null
    ])
    error_message = "Each repository's ruleset must carry at least its tier's rules."
  }

  assert {
    condition     = alltrue([for repo in module.repository : join(",", repo.protection.ruleset.allowed_merge_methods) == "squash" if repo.protection.ruleset != null])
    error_message = "Pull requests must be squash-merged."
  }

  assert {
    condition     = alltrue([for repo in module.repository : join(",", repo.protection.ruleset.bypass) == "OrganizationAdmin via pull_request" if repo.protection.ruleset != null])
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
