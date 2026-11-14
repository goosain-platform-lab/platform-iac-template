# Validation here enforces the naming conventions and GitHub's plan limits, so
# a bad change fails at `terraform plan` with a plain-English message instead
# of failing half-way through an apply. Policy (what we *choose* to allow) is
# enforced separately in tests/.

# --- Environment identity: set in environments/<environment>.tfvars --------

variable "github_org" {
  description = "The GitHub organization this environment manages, e.g. acme-platform-lab-sandbox."
  type        = string

  validation {
    condition     = length(var.github_org) <= 39 && can(regex("^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$", var.github_org))
    error_message = "github_org must be a valid GitHub organization name: letters, numbers and single hyphens, at most 39 characters."
  }
}

variable "github_plan" {
  description = "The org's GitHub plan: free, team or enterprise. It decides which protections GitHub allows (see docs/controls.md)."
  type        = string

  validation {
    condition     = contains(["free", "team", "enterprise"], var.github_plan)
    error_message = "github_plan must be free, team or enterprise."
  }
}

variable "control_repository" {
  description = "The repository holding this code, when it lives in this environment's org. Terraform manages which teams can use it, not the repository itself."
  type = object({
    name        = string
    team_access = map(string)
  })
  default = null

  validation {
    condition     = alltrue([for team in keys(try(var.control_repository.team_access, {})) : contains(keys(var.teams), team)])
    error_message = "control_repository.team_access may only name teams defined in var.teams."
  }

  validation {
    condition     = alltrue([for role in values(try(var.control_repository.team_access, {})) : contains(["read", "triage", "write", "maintain", "admin"], role)])
    error_message = "control_repository.team_access roles must be read, triage, write, maintain or admin."
  }
}

# --- Secrets: supplied by CI, never committed -------------------------------

variable "billing_email" {
  description = "The org's billing email. The provider requires it, but Terraform never changes it (see organization.tf). CI passes it from the ORG_BILLING_EMAIL secret."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.billing_email)) && !can(regex("(?i)@example\\.(com|org|net)$", var.billing_email))
    error_message = "billing_email must be a real email address. In CI set the ORG_BILLING_EMAIL secret; locally set $env:TF_VAR_billing_email."
  }
}

# --- Shared platform config: set in platform.auto.tfvars --------------------

variable "organization_settings" {
  description = "Member privileges and defaults for the org. Every setting is explicit because the provider's own defaults are permissive (members may create repositories and pages)."
  type = object({
    default_repository_permission            = optional(string, "read")
    members_can_create_repositories          = optional(bool, false)
    members_can_create_public_repositories   = optional(bool, false)
    members_can_create_private_repositories  = optional(bool, false)
    members_can_create_internal_repositories = optional(bool, false)
    members_can_create_pages                 = optional(bool, false)
    members_can_create_public_pages          = optional(bool, false)
    members_can_create_private_pages         = optional(bool, false)
    members_can_fork_private_repositories    = optional(bool, false)
    web_commit_signoff_required              = optional(bool, false)
    has_organization_projects                = optional(bool, true)
    has_repository_projects                  = optional(bool, true)
  })
  default = {}

  validation {
    condition     = contains(["none", "read", "write", "admin"], var.organization_settings.default_repository_permission)
    error_message = "default_repository_permission must be none, read, write or admin."
  }
}

variable "actions_policy" {
  description = "Which GitHub Actions may run in the org, and the default GITHUB_TOKEN permissions."
  type = object({
    allowed_actions                  = optional(string, "selected")
    github_owned_allowed             = optional(bool, true)
    verified_allowed                 = optional(bool, false)
    patterns_allowed                 = optional(list(string), [])
    sha_pinning_required             = optional(bool, true)
    default_workflow_permissions     = optional(string, "read")
    can_approve_pull_request_reviews = optional(bool, false)
  })
  default = {}

  validation {
    condition     = contains(["all", "local_only", "selected"], var.actions_policy.allowed_actions)
    error_message = "actions_policy.allowed_actions must be all, local_only or selected."
  }

  validation {
    condition     = contains(["read", "write"], var.actions_policy.default_workflow_permissions)
    error_message = "actions_policy.default_workflow_permissions must be read or write."
  }

  validation {
    condition     = alltrue([for pattern in var.actions_policy.patterns_allowed : can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.*/-]+@\\*$", pattern))])
    error_message = "actions_policy.patterns_allowed entries must look like owner/repo@* (SHA pinning is enforced separately)."
  }
}

variable "teams" {
  description = "Teams to create, keyed by team name. Names are lower-case kebab-case so the name and its slug are identical. Membership is managed by hand."
  type = map(object({
    description = string
    privacy     = optional(string, "closed")
  }))

  validation {
    condition     = alltrue([for name in keys(var.teams) : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", name))])
    error_message = "Team names must be lower-case kebab-case (e.g. lead-developers). Offending: ${join(", ", [for name in keys(var.teams) : name if !can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", name))])}."
  }

  validation {
    condition     = alltrue([for team in values(var.teams) : contains(["closed", "secret"], team.privacy) && length(trimspace(team.description)) > 0])
    error_message = "Each team needs a description, and privacy must be closed or secret."
  }
}

variable "default_team_access" {
  description = "The role each team gets on every managed repository, in GitHub UI terms: read, triage, write, maintain or admin. Override per repository with team_access."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for team in keys(var.default_team_access) : contains(keys(var.teams), team)])
    error_message = "default_team_access may only name teams defined in var.teams. Unknown: ${join(", ", [for team in keys(var.default_team_access) : team if !contains(keys(var.teams), team)])}."
  }

  validation {
    condition     = alltrue([for role in values(var.default_team_access) : contains(["read", "triage", "write", "maintain", "admin"], role)])
    error_message = "default_team_access roles must be read, triage, write, maintain or admin."
  }
}

# --- Classification: custom properties and tiers ---------------------------

variable "custom_properties" {
  description = "The classification schema every managed repository carries, keyed by property name (lower-case kebab-case). The criticality property selects each repository's branch rules (var.tier_policies)."
  type = map(object({
    description    = string
    value_type     = optional(string, "single_select")
    allowed_values = optional(list(string), [])
    required       = optional(bool, false)
    editable_by    = optional(string, "org")
    enabled        = optional(bool, true)
  }))
  default = {}

  validation {
    condition     = alltrue([for name in keys(var.custom_properties) : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", name)) && length(name) <= 75])
    error_message = "Custom property names must be lower-case kebab-case, 75 characters at most. Offending: ${join(", ", [for name in keys(var.custom_properties) : name if !(can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", name)) && length(name) <= 75)])}."
  }

  validation {
    condition     = alltrue([for property in values(var.custom_properties) : length(trimspace(property.description)) > 0])
    error_message = "Every custom property needs a description saying what it is for. GitHub shows it next to the value."
  }

  validation {
    condition     = alltrue([for property in values(var.custom_properties) : contains(["single_select", "string", "true_false", "url"], property.value_type)])
    error_message = "value_type must be single_select, string, true_false or url. multi_select is not supported: a repository's values here are single strings."
  }

  validation {
    condition = alltrue([
      for property in values(var.custom_properties) : property.value_type == "single_select" ? (
        length(property.allowed_values) > 0 && length(property.allowed_values) <= 200 && length(distinct(property.allowed_values)) == length(property.allowed_values)
      ) : length(property.allowed_values) == 0
    ])
    error_message = "A single_select property needs 1 to 200 distinct allowed_values; the other types take none."
  }

  validation {
    condition     = alltrue(flatten([for property in values(var.custom_properties) : [for value in property.allowed_values : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", value)) && length(value) <= 75]]))
    error_message = "Allowed values are lower-case kebab-case and 75 characters at most, like every other name you see in GitHub."
  }

  validation {
    condition     = alltrue([for property in values(var.custom_properties) : contains(["org", "org-and-repo"], property.editable_by)])
    error_message = "editable_by must be org (only org owners and the platform) or org-and-repo (repository admins too)."
  }

  validation {
    condition = try(
      var.custom_properties["criticality"].value_type == "single_select" &&
      var.custom_properties["criticality"].enabled &&
      var.custom_properties["criticality"].required &&
      var.custom_properties["criticality"].editable_by == "org",
      false
    )
    error_message = "Branch rules follow a property named criticality, which must be single_select, switched on, required, and editable by the org only, so no repository can change its own tier."
  }
}

variable "default_repository_properties" {
  description = "Property values every managed repository gets unless it sets its own in properties."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for property in keys(var.default_repository_properties) : contains(keys(var.custom_properties), property)])
    error_message = "default_repository_properties may only name properties defined in var.custom_properties. Unknown: ${join(", ", [for property in keys(var.default_repository_properties) : property if !contains(keys(var.custom_properties), property)])}."
  }
}

variable "tier_policies" {
  description = "The default branch's rules for each criticality tier, keyed by tier. Every repository's ruleset is built from its tier; protected = false means no ruleset at all."
  type = map(object({
    protected                         = optional(bool, true)
    required_approving_review_count   = optional(number, 1)
    require_code_owner_review         = optional(bool, true)
    dismiss_stale_reviews_on_push     = optional(bool, true)
    require_last_push_approval        = optional(bool, false)
    required_review_thread_resolution = optional(bool, true)
    required_linear_history           = optional(bool, false)
    required_signatures               = optional(bool, false)
    required_status_checks            = optional(list(string), [])
  }))

  validation {
    condition = try(
      length(setsubtract(keys(var.tier_policies), var.custom_properties["criticality"].allowed_values)) == 0 &&
      length(setsubtract(var.custom_properties["criticality"].allowed_values, keys(var.tier_policies))) == 0,
      false
    )
    error_message = "tier_policies needs exactly one entry for each allowed value of the criticality property."
  }

  validation {
    condition     = alltrue([for tier in values(var.tier_policies) : tier.required_approving_review_count >= 0 && tier.required_approving_review_count <= 10])
    error_message = "A tier's required_approving_review_count must be between 0 and 10."
  }

  validation {
    condition     = alltrue(flatten([for tier in values(var.tier_policies) : [for check in tier.required_status_checks : length(trimspace(check)) > 0]]))
    error_message = "Required status check names cannot be empty."
  }
}

variable "repositories" {
  description = "Repositories to create and protect, keyed by repository name (lower-case kebab-case, e.g. demo-api). Each one must say why it exists and carry a value for every required custom property."
  type = map(object({
    description                     = string
    visibility                      = optional(string, "public")
    topics                          = optional(list(string), [])
    has_issues                      = optional(bool, true)
    has_wiki                        = optional(bool, false)
    has_projects                    = optional(bool, false)
    is_template                     = optional(bool, false)
    template                        = optional(string)
    properties                      = optional(map(string), {})
    ruleset_enforcement             = optional(string, "active")
    required_approving_review_count = optional(number)
    required_status_checks          = optional(list(string), [])
    team_access                     = optional(map(string), {})
  }))

  validation {
    condition     = alltrue([for name in keys(var.repositories) : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", name))])
    error_message = "Repository names must be lower-case kebab-case (e.g. demo-api). Offending: ${join(", ", [for name in keys(var.repositories) : name if !can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", name))])}."
  }

  validation {
    condition     = alltrue([for repo in values(var.repositories) : length(trimspace(repo.description)) > 0])
    error_message = "Every repository needs a description saying why it exists."
  }

  validation {
    condition     = alltrue([for repo in values(var.repositories) : contains(["public", "private", "internal"], repo.visibility)])
    error_message = "Repository visibility must be public, private or internal."
  }

  validation {
    condition     = var.github_plan != "free" || alltrue([for repo in values(var.repositories) : repo.visibility == "public"])
    error_message = "On GitHub Free, rulesets only work on public repositories, so every repository must be public (or raise github_plan). Not public: ${join(", ", [for name, repo in var.repositories : name if repo.visibility != "public"])}."
  }

  validation {
    condition     = var.github_plan == "enterprise" || alltrue([for repo in values(var.repositories) : repo.visibility != "internal"])
    error_message = "Internal visibility needs GitHub Enterprise Cloud (github_plan = \"enterprise\")."
  }

  validation {
    condition     = alltrue(flatten([for repo in values(var.repositories) : [for topic in repo.topics : can(regex("^[a-z0-9][a-z0-9-]{0,49}$", topic))]]))
    error_message = "Topics must be lower-case letters, numbers and hyphens, at most 50 characters."
  }

  validation {
    condition     = alltrue(flatten([for repo in values(var.repositories) : [for property in keys(repo.properties) : contains(keys(var.custom_properties), property)]]))
    error_message = "A repository's properties may only name properties defined in var.custom_properties. Unknown: ${join(", ", distinct(flatten([for name, repo in var.repositories : [for property in keys(repo.properties) : "${name}: ${property}" if !contains(keys(var.custom_properties), property)]])))}."
  }

  validation {
    condition = alltrue(flatten([
      for name, repo in var.repositories : [
        for property, definition in var.custom_properties :
        contains(keys(merge(var.default_repository_properties, repo.properties)), property)
        if definition.required && definition.enabled
      ]
    ]))
    error_message = "Every repository needs a value for each required custom property (its own, or one from default_repository_properties). Missing: ${join(", ", flatten([for name, repo in var.repositories : [for property, definition in var.custom_properties : "${name}: ${property}" if definition.required && definition.enabled && !contains(keys(merge(var.default_repository_properties, repo.properties)), property)]]))}."
  }

  validation {
    condition = alltrue(flatten([
      for name, repo in var.repositories : [
        for property, value in merge(var.default_repository_properties, repo.properties) : try(
          length(value) <= 75 && (
            var.custom_properties[property].value_type == "single_select" ? contains(var.custom_properties[property].allowed_values, value) :
            var.custom_properties[property].value_type == "true_false" ? contains(["true", "false"], value) :
            var.custom_properties[property].value_type == "url" ? can(regex("^https://", value)) :
            length(trimspace(value)) > 0
          ),
          true # an unknown property is reported by the rule above
        )
      ]
    ]))
    error_message = "A property value must suit its property: one of the allowed values for single_select, true or false for true_false, an https:// address for url, never empty, and 75 characters at most. Offending: ${join(", ", flatten([for name, repo in var.repositories : [for property, value in merge(var.default_repository_properties, repo.properties) : "${name}: ${property} = \"${value}\"" if !try(length(value) <= 75 && (var.custom_properties[property].value_type == "single_select" ? contains(var.custom_properties[property].allowed_values, value) : var.custom_properties[property].value_type == "true_false" ? contains(["true", "false"], value) : var.custom_properties[property].value_type == "url" ? can(regex("^https://", value)) : length(trimspace(value)) > 0), true)]]))}."
  }

  validation {
    condition     = alltrue([for repo in values(var.repositories) : contains(["active", "evaluate", "disabled"], repo.ruleset_enforcement)])
    error_message = "ruleset_enforcement must be active, evaluate or disabled."
  }

  validation {
    condition     = var.github_plan == "enterprise" || alltrue([for repo in values(var.repositories) : repo.ruleset_enforcement != "evaluate"])
    error_message = "Evaluate mode (rules that record what they would block, without blocking) needs GitHub Enterprise Cloud. Use active, or disabled while you adopt an existing repository."
  }

  validation {
    condition = alltrue([
      for repo in values(var.repositories) : repo.required_approving_review_count == null ? true : (
        repo.required_approving_review_count <= 10 &&
        repo.required_approving_review_count >= try(var.tier_policies[merge(var.default_repository_properties, repo.properties)["criticality"]].required_approving_review_count, 0)
      )
    ])
    error_message = "A repository may raise its tier's required approvals, never lower them, and 10 is the most GitHub allows. To need fewer, change its tier. Offending: ${join(", ", [for name, repo in var.repositories : "${name} (${repo.required_approving_review_count})" if repo.required_approving_review_count == null ? false : (repo.required_approving_review_count > 10 || repo.required_approving_review_count < try(var.tier_policies[merge(var.default_repository_properties, repo.properties)["criticality"]].required_approving_review_count, 0))])}."
  }

  validation {
    condition     = alltrue(flatten([for repo in values(var.repositories) : [for check in repo.required_status_checks : length(trimspace(check)) > 0]]))
    error_message = "Required status check names cannot be empty."
  }

  validation {
    condition     = alltrue([for name, repo in var.repositories : repo.template == null ? true : (repo.template != name && !repo.is_template && try(var.repositories[repo.template].is_template, false))])
    error_message = "template must name another repository in var.repositories that has is_template = true, and a template repository is not itself created from one."
  }

  validation {
    condition     = alltrue(flatten([for repo in values(var.repositories) : [for team in keys(repo.team_access) : contains(keys(var.teams), team)]]))
    error_message = "A repository's team_access may only name teams defined in var.teams."
  }

  validation {
    condition     = alltrue(flatten([for repo in values(var.repositories) : [for role in values(repo.team_access) : contains(["none", "read", "triage", "write", "maintain", "admin"], role)]]))
    error_message = "team_access roles must be none, read, triage, write, maintain or admin (none removes a default grant)."
  }
}

# --- Test switch ------------------------------------------------------------

variable "adopt_organization_settings" {
  description = "Adopt the org's existing settings with an import block. Leave this true; only the tests set it to false, because mocked providers cannot import."
  type        = bool
  default     = true
}
