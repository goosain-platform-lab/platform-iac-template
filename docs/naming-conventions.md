# Naming conventions

## The five rules

1. **Anything you see in GitHub or HCP Terraform** (orgs, repositories, teams,
   rulesets, custom properties and their values, status checks, Environments,
   workspaces, Apps, labels, workflow files) is **lower-case kebab-case**:
   `demo-api`, `lead-developers`, `tier-1`, `github-platform-prod`.
2. **Terraform identifiers** (resources, variables, outputs, locals, modules) are
   **snake_case**: `default_team_access`. A resource that exists once is named `this`.
3. **Secrets, variables and environment variables** are **UPPER_SNAKE_CASE**,
   prefixed with the system they belong to: `TF_` (Terraform / HCP), `GH_APP_`
   (GitHub Apps), `ORG_` (org facts). Never start one with `GITHUB_`: GitHub
   reserves that prefix.
4. **One environment, one name.** `sandbox` and `prod` are the same string in the
   tfvars file name, the HCP workspace, the GitHub Environment, the workflow matrix
   and the job name. Searching for `prod` finds every piece of prod, and nothing
   else is called `sandbox` or `prod`: the unprotected tier is `experimental`,
   not `sandbox`.
5. **Enforced, not just written down.** Variable validation rejects badly named
   repositories, teams, properties and property values at `terraform plan`;
   tflint fails CI on any identifier that isn't snake_case; tests and the
   allow-list check cover the rest.

## Every name, with its pattern

| Thing | Pattern | Example | Enforced by |
|---|---|---|---|
| Prod org | `<owner>-<purpose>` | `acme-platform-lab` | n/a |
| Non-prod org | prod name + `-<environment>` | `acme-platform-lab-sandbox` | n/a |
| Environment | short, lower-case | `sandbox`, `prod` | workflows (`environments/<name>.tfvars` must exist) |
| Repository | `<product>-<component>` | `demo-api`, `demo-web` | `var.repositories` validation |
| Team | role, plural, kebab-case | `lead-developers` | `var.teams` validation |
| Ruleset | what it protects | `default-branch-protection` | module (one name for all repos) |
| Custom property | what it describes, kebab-case | `data-classification` | `var.custom_properties` validation |
| Property value | kebab-case, from the property's list | `confidential` | `var.custom_properties` validation |
| Tier | `tier-<n>`, 1 most critical; `experimental` unprotected | `tier-2` | `tier_policies` must match the tiers |
| Required check | the job name, kebab-case | `build-and-test` | template CI and `tier_policies` |
| Template repository | what it seeds | `repository-template` | `var.repositories` validation |
| Template publish branch | `publish-templates-<yyyyMMdd-HHmmss>` | `publish-templates-20261114-093000` | `Publish-Templates.ps1` |
| HCP workspace | `github-platform-<environment>` | `github-platform-sandbox` | composite action (one place) |
| GitHub App | `<owner>-platform-<role>` (globally unique) | `acme-platform-reader` | setup guide |
| Workflow file | `terraform-<verb>.yml` for Terraform runs, `platform-<noun>.yml` for checks on the platform | `terraform-drift.yml`, `platform-health.yml` | convention |
| Job / status check | `<verb> (<environment>)` | `plan (prod)` | required checks in the ruleset |
| Composite action | `<tool>-<purpose>` | `terraform-setup` | convention |
| Issue label | lower-case kebab-case, what it reports | `drift`, `platform-health` | the workflow that owns it |
| Terraform identifier | snake_case, singletons `this` | `github_team.this["readers"]` | tflint |
| Secret / variable | `<SYSTEM>_<WHAT>` | `GH_APP_WRITER_PRIVATE_KEY`, `CI_DEPENDENCY_REVIEW` (org variable read by the template CI) | convention |
| Template placeholder | `{{UPPER_SNAKE_CASE}}` | `{{CODE_OWNERS_TEAM}}` | `Publish-Templates.ps1` refuses unfilled ones |
| Terraform file | one GitHub concept, in full | `organization.tf` | convention |
| Topic | lower-case kebab-case, 50 chars max | `api` | `var.repositories` validation |

Two side effects worth knowing:

- Team names equal their slugs, so CODEOWNERS (`@org/lead-developers`) and API
  calls use exactly the name you see.
- `for_each` keys are the GitHub names, so state addresses read naturally:
  `module.repository["demo-api"]`, `github_team.this["readers"]`.

## Renaming something later

Repositories and teams are keyed by their name. Renaming one in
`platform.auto.tfvars` alone makes Terraform archive the old repository (or delete
the old team, with its members) and create a new, empty one. To rename in place,
add a `moved` block in the same pull request:

```hcl
moved {
  from = module.repository["demo-api"]
  to   = module.repository["orders-api"]
}
```

The plan then shows the repository renamed in place. Its Dependabot settings and
team grants are re-created, which is harmless. For a team, move
`github_team.this["old-name"]` to `github_team.this["new-name"]` the same way;
without the `moved` block the plan stops, because teams are never deleted.

Custom properties are different: GitHub has no rename. Add the new property,
set its values, then retire the old one with a `removed` block
([controls.md](controls.md#nothing-is-deleted)) and delete it in GitHub. Renaming
a value works the same way: add the new value, move repositories to it, then
remove the old one from `allowed_values`.
