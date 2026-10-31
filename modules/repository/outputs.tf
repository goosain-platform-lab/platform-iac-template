output "name" {
  description = "Repository name."
  value       = github_repository.this.name
}

output "html_url" {
  description = "Repository URL."
  value       = github_repository.this.html_url
}

output "visibility" {
  description = "Repository visibility."
  value       = github_repository.this.visibility
}

output "team_access" {
  description = "Effective team permissions on this repository, in API terms (pull, triage, push, maintain, admin)."
  value       = { for team, grant in github_team_repository.this : team => grant.permission }
}

output "protection" {
  description = "A readable summary of how this repository is protected."
  value = {
    ruleset               = github_repository_ruleset.default_branch.name
    required_approvals    = var.required_approving_review_count
    allowed_merge_methods = github_repository_ruleset.default_branch.rules[0].pull_request[0].allowed_merge_methods
    bypass                = [for actor in github_repository_ruleset.default_branch.bypass_actors : "${actor.actor_type} via ${actor.bypass_mode}"]
    archive_on_destroy    = github_repository.this.archive_on_destroy
    # Read back from the planned resource, not the input, so a test notices if
    # the security block ever stops being built for public repositories.
    secret_scanning = var.visibility == "public" ? alltrue([
      github_repository.this.security_and_analysis[0].secret_scanning[0].status == "enabled",
      github_repository.this.security_and_analysis[0].secret_scanning_push_protection[0].status == "enabled",
    ]) : false
    dependabot_alerts  = github_repository_vulnerability_alerts.this.enabled
    dependabot_updates = github_repository_dependabot_security_updates.this.enabled
  }
}
