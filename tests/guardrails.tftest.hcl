# Guardrails: bad config must be rejected at plan time with a clear message,
# before anything reaches GitHub. Each run feeds in one mistake. Run alongside
# baseline.tftest.hcl with an environment's var file (see that file).

mock_provider "github" {}

variables {
  billing_email               = "platform-owner@lab.test"
  adopt_organization_settings = false # mocked providers cannot import
}

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
