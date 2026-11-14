output "repositories" {
  description = "Each managed repository: URL, visibility, tier, effective team permissions and protections."
  value = {
    for name, repo in module.repository : name => {
      url         = repo.html_url
      visibility  = repo.visibility
      tier        = local.repository_tier[name]
      team_access = repo.team_access
      protection  = repo.protection
    }
  }
}

output "classification" {
  description = "Each managed repository's custom property values, as sent to GitHub."
  value = {
    for repo, properties in local.repository_properties : repo => {
      for property, value in properties : property => value if var.custom_properties[property].enabled
    }
  }
}

output "switched_off" {
  description = "Configured but switched off: validated and tested like everything else, never sent to GitHub."
  value = {
    custom_properties = sort([for name, property in var.custom_properties : name if !property.enabled])
  }
}

output "teams" {
  description = "Managed teams and their slugs. Reference a team in CODEOWNERS as @<org>/<slug>."
  value       = { for name, team in github_team.this : name => team.slug }
}
