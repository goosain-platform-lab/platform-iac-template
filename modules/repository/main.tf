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

  # Start with a README so the default branch exists before the ruleset targets
  # it, or, given a template, with a copy of the template's files.
  auto_init = true

  dynamic "template" {
    for_each = var.template == null ? [] : [var.template]

    content {
      owner                = template.value.owner
      repository           = template.value.repository
      include_all_branches = false
    }
  }

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
    ignore_changes = [
      # GitHub treats Advanced Security as always on for public repositories and
      # rejects attempts to set it, so it stays out of config. Ignoring it here
      # stops it showing up as drift.
      security_and_analysis[0].advanced_security,
      # A template only seeds a new repository. Adding one to an existing
      # repository can't change it, so the change is ignored, not planned.
      template,
    ]
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

# The ruleset used to be a single resource. Repositories in an unprotected tier
# now have none, so it is counted; this keeps existing rulesets in place.
moved {
  from = github_repository_ruleset.default_branch
  to   = github_repository_ruleset.default_branch[0]
}

resource "github_repository_ruleset" "default_branch" {
  count = var.branch_rules == null ? 0 : 1

  name        = "default-branch-protection"
  repository  = github_repository.this.name
  target      = "branch"
  enforcement = var.branch_rules.enforcement

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
    required_linear_history = var.branch_rules.required_linear_history
    required_signatures     = var.branch_rules.required_signatures

    pull_request {
      required_approving_review_count   = var.branch_rules.required_approving_review_count
      dismiss_stale_reviews_on_push     = var.branch_rules.dismiss_stale_reviews_on_push
      require_code_owner_review         = var.branch_rules.require_code_owner_review
      require_last_push_approval        = var.branch_rules.require_last_push_approval
      required_review_thread_resolution = var.branch_rules.required_review_thread_resolution
      allowed_merge_methods             = ["squash"]
    }

    dynamic "required_status_checks" {
      for_each = length(var.branch_rules.required_status_checks) > 0 ? [1] : []

      content {
        strict_required_status_checks_policy = true

        dynamic "required_check" {
          for_each = toset(var.branch_rules.required_status_checks)

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
