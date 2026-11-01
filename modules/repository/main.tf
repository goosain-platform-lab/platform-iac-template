resource "github_repository" "this" {
  name        = var.name
  description = var.description
  visibility  = var.visibility
  topics      = var.topics

  has_issues      = var.has_issues
  has_wiki        = var.has_wiki
  has_projects    = var.has_projects
  has_discussions = false

  # A template repository shows "Use this template" and can seed new repositories.
  is_template = var.is_template

  # Start with a README so the default branch exists before the ruleset targets it.
  auto_init = true

  # Squash-only: one commit per pull request keeps the history linear and readable.
  allow_merge_commit          = false
  allow_rebase_merge          = false
  allow_squash_merge          = true
  squash_merge_commit_title   = "PR_TITLE"
  squash_merge_commit_message = "PR_BODY"
  allow_auto_merge            = false
  allow_update_branch         = true
  delete_branch_on_merge      = true

  # Removing a repository from config archives it. Terraform never deletes code.
  archive_on_destroy = true

  dynamic "security_and_analysis" {
    # Secret scanning and push protection are free on public repositories. On
    # private ones they need a GitHub Secret Protection licence, so they are
    # left to the org's code security configuration instead.
    for_each = var.visibility == "public" ? [1] : []

    content {
      secret_scanning {
        status = "enabled"
      }
      secret_scanning_push_protection {
        status = "enabled"
      }
    }
  }

  lifecycle {
    # GitHub treats Advanced Security as always on for public repositories and
    # rejects attempts to set it, so it stays out of config. Ignoring it here
    # stops it showing up as drift.
    ignore_changes = [security_and_analysis[0].advanced_security]
  }
}

# Dependabot alerts first, then Dependabot security-update pull requests,
# which GitHub only allows once alerts are on.
resource "github_repository_vulnerability_alerts" "this" {
  repository = github_repository.this.name
  enabled    = true
}

resource "github_repository_dependabot_security_updates" "this" {
  repository = github_repository.this.name
  enabled    = true

  depends_on = [github_repository_vulnerability_alerts.this]
}

resource "github_repository_ruleset" "default_branch" {
  name        = "default-branch-protection"
  repository  = github_repository.this.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  # Only org owners may bypass, and only by merging a pull request (e.g. a solo
  # maintainer who can't approve their own PR). Nobody pushes straight to the
  # default branch. OrganizationAdmin has no actor ID, so none is set.
  bypass_actors {
    actor_type  = "OrganizationAdmin"
    bypass_mode = "pull_request"
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true

    pull_request {
      required_approving_review_count   = var.required_approving_review_count
      dismiss_stale_reviews_on_push     = true
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_review_thread_resolution = true
      allowed_merge_methods             = ["squash"]
    }

    dynamic "required_status_checks" {
      for_each = length(var.required_status_checks) > 0 ? [1] : []

      content {
        strict_required_status_checks_policy = true

        dynamic "required_check" {
          for_each = toset(var.required_status_checks)

          content {
            context = required_check.value
          }
        }
      }
    }
  }
}

resource "github_team_repository" "this" {
  for_each = var.team_access

  team_id    = each.value.team_id
  repository = github_repository.this.name
  permission = each.value.permission
}
