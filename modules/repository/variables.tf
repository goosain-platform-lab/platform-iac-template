# Inputs are validated by the root module (variables.tf), which knows about
# teams, tiers and the org's plan. This module only builds one repository.

variable "name" {
  description = "Repository name, lower-case kebab-case."
  type        = string
}

variable "description" {
  description = "Why the repository exists. Shown on GitHub."
  type        = string
}

variable "visibility" {
  description = "public, private or internal."
  type        = string
}

variable "topics" {
  description = "Repository topics, for search and grouping."
  type        = list(string)
}

variable "has_issues" {
  description = "Enable GitHub Issues."
  type        = bool
}

variable "has_wiki" {
  description = "Enable the wiki."
  type        = bool
}

variable "has_projects" {
  description = "Enable repository projects."
  type        = bool
}

variable "is_template" {
  description = "Mark the repository as a template, so new repositories can be created from it."
  type        = bool
  default     = false
}

variable "template" {
  description = "Create the repository as a copy of this template repository's files. Only used at creation; null starts from an empty README."
  type = object({
    owner      = string
    repository = string
  })
  default = null
}

variable "branch_rules" {
  description = "The default branch's rules, resolved from the repository's tier by the root module. null means no ruleset (an unprotected tier)."
  type = object({
    enforcement                       = string
    required_approving_review_count   = number
    require_code_owner_review         = bool
    dismiss_stale_reviews_on_push     = bool
    require_last_push_approval        = bool
    required_review_thread_resolution = bool
    required_linear_history           = bool
    required_signatures               = bool
    required_status_checks            = list(string)
  })
  default = null
}

variable "team_access" {
  description = "Teams with access, keyed by team name: the team's ID and its API permission (pull, triage, push, maintain or admin)."
  type = map(object({
    team_id    = string
    permission = string
  }))
}
