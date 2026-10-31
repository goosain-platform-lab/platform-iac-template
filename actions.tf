# Which GitHub Actions may run anywhere in the org. The control repo's own
# workflows run under this policy too: every third-party action they use must
# be in patterns_allowed, or the next run is blocked and the platform locks
# itself out. scripts/check-actions-allowlist.sh enforces that in CI.
resource "github_actions_organization_permissions" "this" {
  enabled_repositories = "all"
  allowed_actions      = var.actions_policy.allowed_actions
  sha_pinning_required = var.actions_policy.sha_pinning_required

  dynamic "allowed_actions_config" {
    for_each = var.actions_policy.allowed_actions == "selected" ? [1] : []

    content {
      github_owned_allowed = var.actions_policy.github_owned_allowed
      verified_allowed     = var.actions_policy.verified_allowed
      patterns_allowed     = var.actions_policy.patterns_allowed
    }
  }
}

# GITHUB_TOKEN starts read-only in every workflow; each workflow asks for what
# it needs in its own permissions: block. Actions may not approve pull requests.
resource "github_actions_organization_workflow_permissions" "this" {
  organization_slug                = var.github_org
  default_workflow_permissions     = var.actions_policy.default_workflow_permissions
  can_approve_pull_request_reviews = var.actions_policy.can_approve_pull_request_reviews
}
