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
  description = "A readable summary of how this repository is protected. Branch rules are null when its tier is unprotected."
  value = {
    # Read back from the planned resources, not the inputs, so a test notices
    # if a rule or a security setting ever stops being built.
    ruleset = one([
      for ruleset in github_repository_ruleset.default_branch : {
        name                      = ruleset.name
        enforcement               = ruleset.enforcement
        required_approvals        = ruleset.rules[0].pull_request[0].required_approving_review_count
        code_owner_review         = ruleset.rules[0].pull_request[0].require_code_owner_review
        dismiss_stale_reviews     = ruleset.rules[0].pull_request[0].dismiss_stale_reviews_on_push
        last_push_approval        = ruleset.rules[0].pull_request[0].require_last_push_approval
        conversations_resolved    = ruleset.rules[0].pull_request[0].required_review_thread_resolution
        allowed_merge_methods     = ruleset.rules[0].pull_request[0].allowed_merge_methods
        linear_history            = ruleset.rules[0].required_linear_history
        signed_commits            = ruleset.rules[0].required_signatures
        no_deletion_or_force_push = ruleset.rules[0].deletion && ruleset.rules[0].non_fast_forward
        required_status_checks    = sort([for check in flatten(ruleset.rules[0].required_status_checks[*].required_check) : check.context])
        bypass                    = [for actor in ruleset.bypass_actors : "${actor.actor_type} via ${actor.bypass_mode}"]
      }
    ])
    archive_on_destroy = github_repository.this.archive_on_destroy
    secret_scanning = var.visibility == "public" ? alltrue([
      github_repository.this.security_and_analysis[0].secret_scanning[0].status == "enabled",
      github_repository.this.security_and_analysis[0].secret_scanning_push_protection[0].status == "enabled",
    ]) : false
    dependabot_alerts  = github_repository_vulnerability_alerts.this.enabled
    dependabot_updates = github_repository_dependabot_security_updates.this.enabled
  }
}

output "template" {
  description = "The template repository this one was created from, as owner/name; null if none."
  value       = one([for template in github_repository.this.template : "${template.owner}/${template.repository}"])
}
