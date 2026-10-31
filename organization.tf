# The org already exists, so its settings are adopted with an import block
# rather than "created". Two reasons:
#  1. It is the honest model: an org is a singleton that Terraform takes over.
#  2. Provider v6.13 sends only non-false booleans on create, so a created
#     resource would leave members_can_create_repositories and friends at
#     GitHub's default (true) until a second apply. Importing makes the first
#     apply an update, which sends every changed value.
# The provider reads the org named in providers.tf, so the import ID is only a
# label. Tests turn the import off because mocked providers cannot import.
import {
  for_each = var.adopt_organization_settings ? toset(["this"]) : toset([])
  to       = github_organization_settings.this
  id       = var.github_org
}

resource "github_organization_settings" "this" {
  billing_email = var.billing_email

  default_repository_permission            = var.organization_settings.default_repository_permission
  members_can_create_repositories          = var.organization_settings.members_can_create_repositories
  members_can_create_public_repositories   = var.organization_settings.members_can_create_public_repositories
  members_can_create_private_repositories  = var.organization_settings.members_can_create_private_repositories
  members_can_create_internal_repositories = var.organization_settings.members_can_create_internal_repositories
  members_can_create_pages                 = var.organization_settings.members_can_create_pages
  members_can_create_public_pages          = var.organization_settings.members_can_create_public_pages
  members_can_create_private_pages         = var.organization_settings.members_can_create_private_pages
  members_can_fork_private_repositories    = var.organization_settings.members_can_fork_private_repositories
  web_commit_signoff_required              = var.organization_settings.web_commit_signoff_required
  has_organization_projects                = var.organization_settings.has_organization_projects
  has_repository_projects                  = var.organization_settings.has_repository_projects

  lifecycle {
    # Destroying this resource doesn't just "unmanage" the org: the provider
    # resets it and overwrites the billing email with email@example.com.
    # To stop managing it, use `terraform state rm` or a removed block.
    prevent_destroy = true

    ignore_changes = [
      # Billing belongs to whoever pays, not the platform: read, never changed.
      billing_email,
      # Public profile fields are not governance settings. Unset, the provider
      # would report them as drift on every plan without being able to fix it.
      name,
      description,
      company,
      email,
      blog,
      location,
      twitter_username,
      # Deprecated "enable for new repositories" switches, superseded by code
      # security configurations. Every repository here is created by Terraform
      # with its security settings explicit, so these are not needed.
      advanced_security_enabled_for_new_repositories,
      dependabot_alerts_enabled_for_new_repositories,
      dependabot_security_updates_enabled_for_new_repositories,
      dependency_graph_enabled_for_new_repositories,
      secret_scanning_enabled_for_new_repositories,
      secret_scanning_push_protection_enabled_for_new_repositories,
    ]
  }
}
