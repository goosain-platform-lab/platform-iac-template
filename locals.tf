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

  # Who may change a property's value on a repository, in GitHub's words.
  property_editors = {
    org            = "org_actors"
    "org-and-repo" = "org_and_repo_actors"
  }

  # Each repository's property values: the defaults, overridden per repository.
  repository_properties = {
    for repo, settings in var.repositories : repo => merge(var.default_repository_properties, settings.properties)
  }

  # One entry per repository and switched-on property. Values of a switched-off
  # property are validated like the rest, but never sent to GitHub.
  repository_property_values = merge([
    for repo, properties in local.repository_properties : {
      for property, value in properties : "${repo}/${property}" => {
        repository = repo
        property   = property
        type       = var.custom_properties[property].value_type
        value      = value
      }
      if var.custom_properties[property].enabled
    }
  ]...)

  # Each repository's tier, and that tier's branch policy.
  repository_tier = {
    for repo, properties in local.repository_properties : repo => properties["criticality"]
  }
  repository_tier_policy = {
    for repo, tier in local.repository_tier : repo => var.tier_policies[tier]
  }

  # The default branch's rules for each repository: its tier's policy. A
  # repository may ask for more (approvals, extra checks), never for less.
  # null means the tier is unprotected, so the repository gets no ruleset.
  repository_branch_rules = {
    for repo, policy in local.repository_tier_policy : repo => (
      policy.protected ? {
        enforcement                       = var.repositories[repo].ruleset_enforcement
        required_approving_review_count   = max(policy.required_approving_review_count, coalesce(var.repositories[repo].required_approving_review_count, 0))
        require_code_owner_review         = policy.require_code_owner_review
        dismiss_stale_reviews_on_push     = policy.dismiss_stale_reviews_on_push
        require_last_push_approval        = policy.require_last_push_approval
        required_review_thread_resolution = policy.required_review_thread_resolution
        required_linear_history           = policy.required_linear_history
        required_signatures               = policy.required_signatures
        required_status_checks            = sort(distinct(concat(policy.required_status_checks, var.repositories[repo].required_status_checks)))
      } : null
    )
  }
}
