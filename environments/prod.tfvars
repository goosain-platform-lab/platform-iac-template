# Prod: changes arrive here only after sandbox applied cleanly and a platform
# owner approved the prod deployment.
github_org  = "goosain-platform-lab"
github_plan = "free"

# This repository lives in the prod org. Terraform grants the access below but
# does not manage the repository itself (see teams.tf).
control_repository = {
  name = "platform-iac-template"
  team_access = {
    platform-owners = "maintain"
  }
}
