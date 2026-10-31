# Naming conventions

## The five rules

1. **Anything you see in GitHub or HCP Terraform** (orgs, repositories, teams,
   rulesets, Environments, workspaces, Apps, labels, workflow files) is
   **lower-case kebab-case**: `demo-api`, `lead-developers`, `github-platform-prod`.
2. **Terraform identifiers** (resources, variables, outputs, locals, modules) are
   **snake_case**: `default_team_access`. A resource that exists once is named `this`.
3. **Secrets, variables and environment variables** are **UPPER_SNAKE_CASE**,
   prefixed with the system they belong to: `TF_` (Terraform / HCP), `GH_APP_`
   (GitHub Apps), `ORG_` (org facts). Never start one with `GITHUB_`: GitHub
   reserves that prefix.
4. **One environment, one name.** `sandbox` and `prod` are the same string in the
   tfvars file name, the HCP workspace, the GitHub Environment, the workflow matrix
   and the job name. Searching for `prod` finds every piece of prod.
5. **Enforced, not just written down.** Variable validation rejects badly named
   repositories and teams at `terraform plan`; tflint fails CI on any identifier
   that isn't snake_case; tests and the allow-list check cover the rest.

## Every name, with its pattern

| Thing | Pattern | Example | Enforced by |
|---|---|---|---|
| Prod org | `<owner>-<purpose>` | `acme-platform-lab` | n/a |
| Non-prod org | prod name + `-<environment>` | `acme-platform-lab-sandbox` | n/a |
| Environment | short, lower-case | `sandbox`, `prod` | workflows (`environments/<name>.tfvars` must exist) |
| Repository | `<product>-<component>` | `demo-api`, `demo-web` | `var.repositories` validation |
| Team | role, plural, kebab-case | `lead-developers` | `var.teams` validation |
| Ruleset | what it protects | `default-branch-protection` | module (one name for all repos) |
| HCP workspace | `github-platform-<environment>` | `github-platform-sandbox` | composite action (one place) |
| GitHub App | `<owner>-platform-<role>` (globally unique) | `acme-platform-reader` | setup guide |
| Workflow file | `terraform-<verb>.yml` | `terraform-drift.yml` | convention |
| Job / status check | `<verb> (<environment>)` | `plan (prod)` | required checks in the ruleset |
| Composite action | `<tool>-<purpose>` | `terraform-setup` | convention |
| Issue label | lower-case noun | `drift` | drift workflow |
| Terraform identifier | snake_case, singletons `this` | `github_team.this["readers"]` | tflint |
| Secret / variable | `<SYSTEM>_<WHAT>` | `GH_APP_WRITER_PRIVATE_KEY` | convention |
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
`github_team.this["old-name"]` to `github_team.this["new-name"]` the same way.
