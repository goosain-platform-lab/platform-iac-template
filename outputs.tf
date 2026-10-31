output "repositories" {
  description = "Each managed repository: URL, visibility, effective team permissions and protections."
  value = {
    for name, repo in module.repository : name => {
      url         = repo.html_url
      visibility  = repo.visibility
      team_access = repo.team_access
      protection  = repo.protection
    }
  }
}

output "teams" {
  description = "Managed teams and their slugs. Reference a team in CODEOWNERS as @<org>/<slug>."
  value       = { for name, team in github_team.this : name => team.slug }
}
