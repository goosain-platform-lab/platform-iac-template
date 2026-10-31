# Shared platform config: identical in every environment, loaded automatically.
# A change here is planned against sandbox AND prod in the same pull request,
# applied to sandbox first, then to prod after approval.
# Only environment identity (which org, which plan) lives in environments/*.tfvars.

organization_settings = {
  # Public repositories are readable by everyone anyway; on a paid plan with
  # private repositories, set this to "none" so access comes only from teams.
  default_repository_permission = "read"

  members_can_create_repositories          = false
  members_can_create_public_repositories   = false
  members_can_create_private_repositories  = false
  members_can_create_internal_repositories = false
  members_can_create_pages                 = false
  members_can_create_public_pages          = false
  members_can_create_private_pages         = false
  members_can_fork_private_repositories    = false
  web_commit_signoff_required              = false
  has_organization_projects                = true
  has_repository_projects                  = true
}

actions_policy = {
  # Only GitHub-owned actions plus this explicit list. Every third-party action
  # used under .github/ must appear here (CI checks this, see actions.tf).
  allowed_actions      = "selected"
  github_owned_allowed = true
  verified_allowed     = false
  patterns_allowed = [
    "hashicorp/setup-terraform@*",
    "terraform-linters/setup-tflint@*",
  ]
  sha_pinning_required             = true
  default_workflow_permissions     = "read"
  can_approve_pull_request_reviews = false
}

# Team names are lower-case kebab-case, so the name and the slug match.
teams = {
  platform-owners = {
    description = "Platform owners and production approvers. Members should be org Owners; membership is managed by hand."
  }
  architects = {
    description = "Architecture review"
  }
  lead-developers = {
    description = "Lead developers and code reviewers"
  }
  developers = {
    description = "Project developers"
  }
  readers = {
    description = "Read-only access to every managed repository"
  }
}

# The role each team gets on every managed repository (GitHub UI names).
# platform-owners has no standing grant: its members are org Owners already.
default_team_access = {
  architects      = "read"
  lead-developers = "maintain"
  developers      = "write"
  readers         = "read"
}

repositories = {
  demo-api = {
    description = "Sample API service, managed by the platform baseline"
    topics      = ["demo", "api"]
  }

  demo-web = {
    description = "Sample web front end, managed by the platform baseline"
    topics      = ["demo", "web"]
  }
}
