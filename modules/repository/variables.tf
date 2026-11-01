# Inputs are validated by the root module (variables.tf), which knows about
# teams and the org's plan. This module only builds one repository.

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

variable "required_approving_review_count" {
  description = "Approvals a pull request needs before it can merge into the default branch."
  type        = number
}

variable "required_status_checks" {
  description = "Status check names (job names) that must pass before merging. Empty means none."
  type        = list(string)
}

variable "team_access" {
  description = "Teams with access, keyed by team name: the team's ID and its API permission (pull, triage, push, maintain or admin)."
  type = map(object({
    team_id    = string
    permission = string
  }))
}
