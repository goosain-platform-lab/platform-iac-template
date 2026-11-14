# Guardrails: bad config must be rejected at plan time with a clear message,
# before anything reaches GitHub. Each run feeds in one mistake. Run alongside
# baseline.tftest.hcl with an environment's var file (see that file).

mock_provider "github" {}

variables {
  billing_email               = "platform-owner@lab.test"
  adopt_organization_settings = false # mocked providers cannot import

  # Every required property gets a value here, so the runs below that bring
  # their own repositories only need to say what they are testing.
  default_repository_properties = {
    criticality            = "tier-3"
    lifecycle              = "active"
    data-classification    = "public"
    contains-personal-data = "no"
    technical-owner        = "lead-developers"
  }
}

# --- Repositories and access ---------------------------------------------------

run "rejects_repository_names_that_are_not_kebab_case" {
  command = plan
  variables {
    repositories = { Demo_API = { description = "Wrong case and an underscore" } }
  }
  expect_failures = [var.repositories]
}

run "rejects_repositories_without_a_description" {
  command = plan
  variables {
    repositories = { demo-empty = { description = "   " } }
  }
  expect_failures = [var.repositories]
}

run "rejects_private_repositories_on_the_free_plan" {
  command = plan
  variables {
    github_plan  = "free"
    repositories = { demo-private = { description = "Rulesets would silently not apply", visibility = "private" } }
  }
  expect_failures = [var.repositories]
}

run "allows_private_repositories_on_a_paid_plan_without_secret_scanning" {
  command = plan
  variables {
    github_plan  = "team"
    repositories = { demo-private = { description = "Private on a paid plan", visibility = "private" } }
  }
  assert {
    condition     = module.repository["demo-private"].protection.secret_scanning == false
    error_message = "Private repositories must not try to enable secret scanning (it needs a separate licence)."
  }
}

run "rejects_internal_repositories_below_enterprise" {
  command = plan
  variables {
    github_plan  = "team"
    repositories = { demo-internal = { description = "Internal needs Enterprise Cloud", visibility = "internal" } }
  }
  expect_failures = [var.repositories]
}

run "rejects_team_names_that_are_not_kebab_case" {
  command = plan
  variables {
    teams               = { LeadDevs = { description = "Name would not match its slug" } }
    default_team_access = {}
    control_repository  = null
  }
  expect_failures = [var.teams]
}

run "rejects_unknown_teams_in_default_access" {
  command = plan
  variables {
    default_team_access = { ghosts = "read" }
  }
  expect_failures = [var.default_team_access]
}

run "rejects_unknown_teams_in_repository_access" {
  command = plan
  variables {
    repositories = { demo-api = { description = "Grants a team that does not exist", team_access = { ghosts = "write" } } }
  }
  expect_failures = [var.repositories]
}

run "rejects_unknown_roles" {
  command = plan
  variables {
    default_team_access = { developers = "owner" }
  }
  expect_failures = [var.default_team_access]
}

run "none_removes_a_default_grant" {
  command = plan
  variables {
    repositories = { demo-api = { description = "Readers removed here", team_access = { readers = "none" } } }
  }
  assert {
    condition     = !contains(keys(module.repository["demo-api"].team_access), "readers")
    error_message = "A role of none must remove the default grant for that repository."
  }
}

run "rejects_placeholder_billing_email" {
  command = plan
  variables {
    billing_email = "you@example.com"
  }
  expect_failures = [var.billing_email]
}

run "rejects_action_patterns_that_pin_a_tag" {
  command = plan
  variables {
    actions_policy = { patterns_allowed = ["hashicorp/setup-terraform@v4"] }
  }
  expect_failures = [var.actions_policy]
}

# --- Classification ------------------------------------------------------------

run "rejects_properties_that_are_not_defined" {
  command = plan
  variables {
    repositories = { demo-api = { description = "Sets a property nobody defined", properties = { cost-centre = "finance" } } }
  }
  expect_failures = [var.repositories]
}

run "rejects_values_a_property_does_not_allow" {
  command = plan
  variables {
    repositories = { demo-api = { description = "Not a tier", properties = { criticality = "tier-0" } } }
  }
  expect_failures = [var.repositories]
}

run "rejects_repositories_missing_a_required_property" {
  command = plan
  variables {
    default_repository_properties = { lifecycle = "active" }
    repositories                  = { demo-api = { description = "Never classified" } }
  }
  expect_failures = [var.repositories]
}

run "rejects_a_tier_that_repository_admins_can_change" {
  command = plan
  variables {
    custom_properties = {
      criticality = {
        description    = "Tier, but editable by repository admins"
        allowed_values = ["tier-1", "tier-2", "tier-3", "experimental"]
        required       = true
        editable_by    = "org-and-repo"
      }
    }
    default_repository_properties = { criticality = "tier-3" }
  }
  expect_failures = [var.custom_properties]
}

# The runs below bring a small schema of their own: the tier property and the
# one they are testing. Test variables cannot call functions such as merge().

run "rejects_multi_select_properties" {
  command = plan
  variables {
    custom_properties = {
      criticality = { description = "Tier", allowed_values = ["tier-1", "tier-2", "tier-3", "experimental"], required = true }
      languages   = { description = "Several values per repository", value_type = "multi_select", allowed_values = ["go", "python"] }
    }
    default_repository_properties = { criticality = "tier-3" }
    repositories                  = { demo-api = { description = "Sample" } }
  }
  expect_failures = [var.custom_properties]
}

run "rejects_allowed_values_that_are_not_kebab_case" {
  command = plan
  variables {
    custom_properties = {
      criticality = { description = "Tier", allowed_values = ["tier-1", "tier-2", "tier-3", "experimental"], required = true }
      region      = { description = "Hosting region", allowed_values = ["South Africa North"] }
    }
    default_repository_properties = { criticality = "tier-3" }
    repositories                  = { demo-api = { description = "Sample" } }
  }
  expect_failures = [var.custom_properties]
}

run "rejects_url_values_that_are_not_https" {
  command = plan
  variables {
    custom_properties = {
      criticality = { description = "Tier", allowed_values = ["tier-1", "tier-2", "tier-3", "experimental"], required = true }
      runbook     = { description = "Where the runbook lives", value_type = "url" }
    }
    default_repository_properties = { criticality = "tier-3" }
    repositories                  = { demo-api = { description = "Plain HTTP runbook", properties = { runbook = "http://wiki.lab.test/demo-api" } } }
  }
  expect_failures = [var.repositories]
}

run "switched_off_properties_never_reach_github" {
  command = plan
  variables {
    custom_properties = {
      criticality = { description = "Tier", allowed_values = ["tier-1", "tier-2", "tier-3", "experimental"], required = true }
      cost-centre = { description = "Waits on a finance decision", allowed_values = ["finance", "operations"], enabled = false }
    }
    default_repository_properties = { criticality = "tier-3" }
    repositories                  = { demo-api = { description = "Already labelled for later", properties = { cost-centre = "finance" } } }
  }
  assert {
    condition     = !contains(keys(github_organization_custom_properties.this), "cost-centre") && !contains(keys(github_repository_custom_property.this), "demo-api/cost-centre")
    error_message = "A switched-off property must be validated but never created, and its values never set."
  }
  assert {
    condition     = contains(output.switched_off.custom_properties, "cost-centre") && contains(keys(github_repository_custom_property.this), "demo-api/criticality")
    error_message = "Switched-off entries must be listed in the switched_off output, and switched-on ones still set."
  }
}

# --- Tiers and branch rules ----------------------------------------------------

run "rejects_tier_policies_that_do_not_cover_every_tier" {
  command = plan
  variables {
    tier_policies = {
      tier-1 = { required_approving_review_count = 2 }
      tier-2 = { required_approving_review_count = 2 }
    }
  }
  expect_failures = [var.tier_policies]
}

run "experimental_repositories_get_no_ruleset" {
  command = plan
  variables {
    repositories = { demo-spike = { description = "A throwaway experiment", properties = { criticality = "experimental" } } }
  }
  assert {
    condition     = module.repository["demo-spike"].protection.ruleset == null
    error_message = "The experimental tier is unprotected: no ruleset."
  }
}

run "tier_1_repositories_get_the_strictest_rules" {
  command = plan
  variables {
    repositories = { demo-payments = { description = "Critical service", properties = { criticality = "tier-1" } } }
  }
  assert {
    condition = alltrue([
      module.repository["demo-payments"].protection.ruleset.required_approvals == 2,
      module.repository["demo-payments"].protection.ruleset.code_owner_review,
      module.repository["demo-payments"].protection.ruleset.linear_history,
      contains(module.repository["demo-payments"].protection.ruleset.required_status_checks, "build-and-test"),
    ])
    error_message = "A tier-1 repository must get two approvals, a code owner review, linear history and the build-and-test check."
  }
}

run "repositories_may_raise_their_tier" {
  command = plan
  variables {
    repositories = {
      demo-api = {
        description                     = "Asks for more than tier-2"
        properties                      = { criticality = "tier-2" }
        required_approving_review_count = 3
        required_status_checks          = ["integration-tests"]
      }
    }
  }
  assert {
    condition     = module.repository["demo-api"].protection.ruleset.required_approvals == 3
    error_message = "A repository may raise its tier's required approvals."
  }
  assert {
    condition     = join(",", module.repository["demo-api"].protection.ruleset.required_status_checks) == "build-and-test,integration-tests"
    error_message = "A repository's own checks must be added to its tier's, not replace them."
  }
}

run "rejects_lowering_a_tier" {
  command = plan
  variables {
    repositories = { demo-api = { description = "Asks for fewer approvals than tier-3", required_approving_review_count = 1 } }
  }
  expect_failures = [var.repositories]
}

run "rejects_evaluate_mode_below_enterprise" {
  command = plan
  variables {
    github_plan  = "team"
    repositories = { demo-api = { description = "Evaluate needs Enterprise Cloud", ruleset_enforcement = "evaluate" } }
  }
  expect_failures = [var.repositories]
}

run "allows_evaluate_mode_on_enterprise" {
  command = plan
  variables {
    github_plan  = "enterprise"
    repositories = { demo-api = { description = "Adopted gradually", ruleset_enforcement = "evaluate" } }
  }
  assert {
    condition     = module.repository["demo-api"].protection.ruleset.enforcement == "evaluate"
    error_message = "On Enterprise Cloud a repository may start in evaluate mode."
  }
}

# --- Templates -----------------------------------------------------------------

run "rejects_a_template_that_is_not_a_template_repository" {
  command = plan
  variables {
    repositories = {
      demo-api    = { description = "Not a template" }
      demo-worker = { description = "Created from a repository that is not a template", template = "demo-api" }
    }
  }
  expect_failures = [var.repositories]
}

run "creates_new_repositories_from_the_template" {
  command = plan
  variables {
    repositories = {
      repository-template = { description = "The template", is_template = true }
      demo-worker         = { description = "Starts from the template", template = "repository-template" }
    }
  }
  assert {
    condition     = module.repository["demo-worker"].template == "${var.github_org}/repository-template"
    error_message = "A repository that names a template must be created from that template, in the same org."
  }
  assert {
    condition     = module.repository["demo-worker"].protection.ruleset.name == "default-branch-protection" && module.repository["repository-template"].template == null
    error_message = "A repository created from a template still gets its tier's ruleset, and the template itself starts empty."
  }
}
