# Credentials never live in code. The provider reads GITHUB_TOKEN:
#   CI     a one-hour GitHub App installation token minted per job by
#          .github/actions/terraform-setup (reader App for plan and drift,
#          writer App for apply).
#   Local  your own token, for plans only:   $env:GITHUB_TOKEN = gh auth token
provider "github" {
  owner = var.github_org
}
