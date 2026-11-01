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
    # Used by the workload templates to sign in to Azure with OIDC.
    "azure/login@*",
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

  # Azure web app building blocks: resource modules -> patterns -> workload templates.
  # Modules are consumed by tag (git::...?ref=vX.Y.Z), so each repo keeps its release tags.

  terraform-azurerm-resource-storage = {
    description = "Terraform module: one Azure Storage account (sta{environment}{purpose}zan naming)"
    topics      = ["terraform", "azure", "terraform-module"]
  }

  terraform-azurerm-resource-windows-web-app = {
    description = "Terraform module: one Windows App Service site with a managed identity"
    topics      = ["terraform", "azure", "terraform-module"]
  }

  terraform-azurerm-resource-linux-web-app = {
    description = "Terraform module: one Linux App Service site with a managed identity"
    topics      = ["terraform", "azure", "terraform-module"]
  }

  terraform-azurerm-resource-sql-database-sep = {
    description = "Terraform module: a database in an Azure SQL elastic pool"
    topics      = ["terraform", "azure", "terraform-module"]
  }

  terraform-azurerm-resource-application-insights = {
    description = "Terraform module: workspace-based Application Insights and the site settings to wire it in"
    topics      = ["terraform", "azure", "terraform-module"]
  }

  terraform-azurerm-resource-locks = {
    description = "Terraform module: management locks for the resources of a web app deployment"
    topics      = ["terraform", "azure", "terraform-module"]
  }

  terraform-azurerm-utility-webapp-context = {
    description = "Terraform module: resolves shared infrastructure for a web app by naming convention"
    topics      = ["terraform", "azure", "terraform-module"]
  }

  terraform-azurerm-pattern-web-app-1tier = {
    description = "Terraform pattern: one App Service site with insights, database and locks"
    topics      = ["terraform", "azure", "terraform-module"]
  }

  terraform-azurerm-pattern-web-app-2tier = {
    description = "Terraform pattern: web + api App Service pair with insights, database and locks"
    topics      = ["terraform", "azure", "terraform-module"]
  }

  terraform-azurerm-pattern-web-app-3tier = {
    description = "Terraform pattern: web, api and backoffice App Service sites with insights, database and locks"
    topics      = ["terraform", "azure", "terraform-module"]
  }

  terraform-azurerm-template-workload-1tier = {
    description = "Template: 1-tier web app workload (a single site)"
    topics      = ["terraform", "azure", "template"]
    is_template = true
  }

  terraform-azurerm-template-workload-2tier = {
    description = "Template: 2-tier web app workload (frontend + api)"
    topics      = ["terraform", "azure", "template"]
    is_template = true
  }

  terraform-azurerm-template-workload-3tier = {
    description = "Template: 3-tier web app workload (frontend, api, backoffice)"
    topics      = ["terraform", "azure", "template"]
    is_template = true
  }

  terraform-azurerm-tooling = {
    description = "Tooling for web app workloads: prerequisite scripts, module releases and workflow sync"
    topics      = ["terraform", "azure", "powershell", "tooling"]
  }
}
