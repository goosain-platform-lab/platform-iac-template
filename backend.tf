# State lives in HCP Terraform (free tier). Nothing is hard-coded, so the same
# code serves every environment. Terraform reads two environment variables:
#
#   TF_CLOUD_ORGANIZATION   your HCP Terraform organization
#   TF_WORKSPACE            github-platform-<environment>, e.g. github-platform-sandbox
#
# The workspace must already exist and use the "Local" execution mode: HCP
# Terraform stores, versions and locks the state, while plans and applies run on
# the GitHub Actions runner. Terraform deliberately never creates a workspace
# from TF_WORKSPACE; scripts/Initialize-ControlRepo.ps1 creates both.
terraform {
  cloud {}
}
