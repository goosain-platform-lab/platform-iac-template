plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.33.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Lab environments are destroyed and redeployed by design, so prevent_destroy
# would block the normal workflow. Turn this back on for a long-lived deployment.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}

# Auto-heal restarts an app when it misbehaves, which hides the cause.
# Failures are surfaced through Application Insights instead.
rule "azurerm_app_service_missing_auto_heal_setting" {
  enabled = false
}
