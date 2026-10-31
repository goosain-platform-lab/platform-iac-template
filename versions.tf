terraform {
  # 1.9+ lets a variable's validation check other variables (for example, a
  # repository may only grant access to teams that exist). CI installs the exact
  # version pinned in .terraform-version.
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
  }
}
