# Shared platform config: identical in every environment, loaded automatically.
# A change here is planned against sandbox AND prod in the same pull request,
# applied to sandbox first, then to prod after approval.
# Only environment identity (which org, which plan) lives in environments/*.tfvars.

organization_settings = {
  # Least privilege: access comes only from team grants. On public repositories
  # everyone can read anyway; on private ones, "read" would open every
  # repository to every member.
  default_repository_permission = "none"

  members_can_create_repositories          = false
  members_can_create_public_repositories   = false
  members_can_create_private_repositories  = false
  members_can_create_internal_repositories = false
  members_can_create_pages                 = false
  members_can_create_public_pages          = false
  members_can_create_private_pages         = false
  members_can_fork_private_repositories    = false

  # Commits made in the web editor carry the author's sign-off, so every change
  # is attributable. Signed commits stay off: see tier-1 below.
  web_commit_signoff_required = true

  has_organization_projects = true
  has_repository_projects   = true
}

actions_policy = {
  # Only GitHub-owned actions plus this explicit list. Every third-party action
  # used under .github/ or templates/ must appear here (CI checks this, see
  # actions.tf). Verified Marketplace creators stay off: each third-party
  # action is reviewed and listed by name.
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
    description = "Lead developers: code owners of every repository created from the template"
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
# Terraform repositories give it maintain with team_access, because GitHub
# counts a code-owner team's approval only when the team itself can write.
default_team_access = {
  architects      = "read"
  lead-developers = "maintain"
  developers      = "write"
  readers         = "read"
}

# --- Classification ----------------------------------------------------------
# Every managed repository carries these properties. GitHub shows them on the
# repository and lets you filter by them (props.criticality:tier-1). Values are
# lower-case kebab-case, like every other name you see in GitHub.

custom_properties = {
  criticality = {
    description    = "Criticality tier. Selects the branch rules the repository gets."
    allowed_values = ["tier-1", "tier-2", "tier-3", "experimental"]
    required       = true
    editable_by    = "org" # a repository must not be able to lower its own tier
  }
  lifecycle = {
    description    = "Lifecycle stage. Keeps dormant and migrating repositories out of active-estate reporting."
    allowed_values = ["active", "maintenance", "migrating", "retiring"]
    required       = true
  }
  data-classification = {
    description    = "Information classification of what the repository holds."
    allowed_values = ["public", "internal", "confidential", "restricted"]
    required       = true
  }
  contains-personal-data = {
    description    = "Whether the repository holds personal data. unknown is a finding to resolve, not an answer."
    allowed_values = ["yes", "no", "unknown"]
    required       = true
  }
  technical-owner = {
    description = "Slug of the team that owns the repository: the escalation route."
    value_type  = "string"
    required    = true
    editable_by = "org-and-repo" # repository admins keep it current
  }
  migrated-from = {
    description = "Source of a migrated repository, e.g. an Azure DevOps organisation/project."
    value_type  = "string"
    # Switched off until the first migration wave: validated and tested, never
    # sent to GitHub. Switching it on is a one-line pull request.
    enabled = false
  }
}

# Values every repository gets unless it sets its own.
default_repository_properties = {
  lifecycle = "active"
}

# --- Branch rules per tier ---------------------------------------------------
# Every repository's default branch gets its tier's rules. A repository may ask
# for more (approvals, extra checks) but never for less: to need less, change
# its tier. All tiers keep squash-only merges, no force-push and no deletion,
# and only org owners may bypass, through a pull request.

tier_policies = {
  # Critical, customer-facing systems.
  tier-1 = {
    required_approving_review_count   = 2
    require_code_owner_review         = true
    dismiss_stale_reviews_on_push     = true
    required_review_thread_resolution = true
    required_linear_history           = true
    # Off until there is a signing-key policy: without one nobody can sign,
    # and every change to a tier-1 repository would be blocked.
    required_signatures = false
    # The job name in the template's CI, so repositories created from the
    # template report it from their first pull request.
    required_status_checks = ["build-and-test"]
  }

  # Business systems.
  tier-2 = {
    required_approving_review_count   = 2
    require_code_owner_review         = true
    dismiss_stale_reviews_on_push     = true
    required_review_thread_resolution = true
    required_status_checks            = ["build-and-test"]
  }

  # Internal tooling, samples and templates.
  tier-3 = {
    required_approving_review_count   = 2
    require_code_owner_review         = true
    dismiss_stale_reviews_on_push     = false
    required_review_thread_resolution = false
  }

  # Throwaway experiments: no ruleset at all. Nothing that ships lives here.
  experimental = {
    protected = false
  }
}

# --- Repositories ------------------------------------------------------------
# New repositories start from a template (see templates/ and docs/templates.md):
#   repository-template        applications: lead developers are the code owners
#   terraform-module-template  Terraform: platform owners are the code owners, so
#                              give them a role with team_access, as below

repositories = {
  demo-api = {
    description = "Sample API service, managed by the platform baseline"
    topics      = ["demo", "api"]
    properties = {
      criticality            = "tier-3"
      data-classification    = "public"
      contains-personal-data = "no"
      technical-owner        = "lead-developers"
    }
  }

  demo-web = {
    description = "Sample web front end, managed by the platform baseline"
    topics      = ["demo", "web"]
    properties = {
      criticality            = "tier-3"
      data-classification    = "public"
      contains-personal-data = "no"
      technical-owner        = "lead-developers"
    }
  }

  terraform-azurerm-ai-stt = {
    description = "Terraform module: secretless real-time speech-to-text and translation workload on Azure"
    template    = "repository-template"
    topics      = ["terraform", "terraform-module", "azure", "speech-to-text", "secretless"]
    properties = {
      criticality            = "tier-3"
      data-classification    = "public"
      contains-personal-data = "no"
      technical-owner        = "platform-owners"
    }
    # Platform owners are the code owners and approve every change.
    team_access = { platform-owners = "maintain" }
  }

  terraform-azurerm-ai-stt-batch = {
    description = "Terraform module: secretless speech batch pipeline (Service Bus, Functions, SQL, Azure OpenAI) on Azure"
    template    = "repository-template"
    topics      = ["terraform", "terraform-module", "azure", "speech-to-text", "secretless"]
    properties = {
      criticality            = "tier-3"
      data-classification    = "public"
      contains-personal-data = "no"
      technical-owner        = "platform-owners"
    }
    # Platform owners are the code owners and approve every change.
    team_access = { platform-owners = "maintain" }
  }

  ai-landing-zone-lab = {
    description = "Azure AI application landing zone in Terraform: governed private spoke hosting RAG and speech workloads"
    template    = "repository-template"
    topics      = ["terraform", "azure", "landing-zone", "azure-openai", "secretless"]
    properties = {
      criticality            = "tier-3"
      data-classification    = "public"
      contains-personal-data = "no"
      technical-owner        = "platform-owners"
    }
    # Platform owners are the code owners and approve every change.
    team_access = { platform-owners = "maintain" }
  }

  terraform-azurerm-aks = {
    description = "Terraform module: private, secretless AKS with workload identity, Cilium and Flux GitOps"
    template    = "repository-template"
    topics      = ["terraform", "terraform-module", "azure", "kubernetes", "aks", "gitops"]
    properties = {
      criticality            = "tier-3"
      data-classification    = "public"
      contains-personal-data = "no"
      technical-owner        = "platform-owners"
    }
    # Platform owners are the code owners and approve every change.
    team_access = { platform-owners = "maintain" }
  }

  repository-template = {
    description = "Starting point for new repositories. Its files are published from templates/ in the platform repository; change them there"
    topics      = ["platform", "template"]
    is_template = true
    properties = {
      criticality            = "tier-3"
      data-classification    = "public"
      contains-personal-data = "no"
      technical-owner        = "platform-owners"
    }
  }

  terraform-module-template = {
    description = "Starting point for Terraform repositories, code-owned by the platform owners. Its files are published from templates/ in the platform repository; change them there"
    topics      = ["platform", "template", "terraform"]
    is_template = true
    properties = {
      criticality            = "tier-3"
      data-classification    = "public"
      contains-personal-data = "no"
      technical-owner        = "platform-owners"
    }
    team_access = { platform-owners = "maintain" }
  }
}
