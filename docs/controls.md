# Controls

What each control does, where it lives, why it exists and how to check it.
The decisions behind the bigger ones are recorded in [docs/adr](adr/).

## Change control

| Control | Where | Why | How to check |
|---|---|---|---|
| Changes reach main only by pull request | Control repo ruleset `default-branch-protection` (bootstrap step 6) | Every change is reviewed and recorded | `git push origin main` is rejected |
| Every PR is planned against both environments | `terraform-plan.yml` | The reviewer sees the exact effect on sandbox and prod before merging | One plan comment per environment |
| Static checks run before any plan | `checks` job: fmt, validate, tflint, tests, allow-list, health check tests, script parsing | Mistakes fail before a single API call | Break the formatting: `checks` fails |
| Sandbox first, prod second | `terraform-apply.yml`: `apply-prod` needs `apply-sandbox` | A change that breaks sandbox never reaches prod | A failed sandbox apply: prod never starts |
| Prod waits for a person | `prod` Environment, required reviewer | Human approval before prod changes | The run pauses at "Waiting for review" |
| One apply at a time | `concurrency: terraform-apply` plus the HCP state lock | Two applies can't race on the same org | A second run queues behind the first |

## Credentials

| Control | Where | Why | How to check |
|---|---|---|---|
| No personal access tokens | Two GitHub Apps; tokens minted per job in `terraform-setup` | Tokens last one hour and belong to an App, not a person | The token step in any job log |
| Pull requests, drift and health checks are read-only | Reader App, read-only permissions | No pull request, even a malicious one, can change GitHub | The reader App's permissions page |
| The writer key is reachable only from main | `GH_APP_WRITER_PRIVATE_KEY` is an Environment secret; both Environments accept main only | Workflow code on a PR branch can't read it | Environment settings > Deployment branches |
| HCP team token with an expiry | `TF_API_TOKEN` | Organization tokens can't run Terraform; user tokens are tied to a person | HCP > Settings > API tokens |
| The checkout token isn't left behind | `persist-credentials: false` on every checkout | Later steps can't reuse it | The workflow files |
| Secrets never enter git or logs | `*.pem` ignored; tfvars hold config only; `billing_email` is `sensitive`; push protection on this repo | Nothing secret is committed or printed | Push a fake key: push protection blocks it |
| Both Apps hold exactly the permissions they need | `platform-health` compares each installation with `scripts/platform-health.json` | A missed permission update or a quietly widened App is caught the next morning | Remove a permission: the health issue opens |

## Organization baseline (`organization.tf`, `actions.tf`)

| Control | Why | How to check |
|---|---|---|
| Members can't create repositories or Pages | Every repository goes through this code and gets the baseline | Org settings > Member privileges; also tested |
| Base permission `none` | Least privilege: access comes only from team grants. Public repositories stay readable by everyone anyway | Org settings > Member privileges; tested |
| Web commits carry a sign-off | Every change made in the browser is attributable to a person | Edit a file in the web editor: the sign-off is added |
| Only GitHub-owned and allow-listed actions run | A third-party action is someone else's code running with your secrets | Org settings > Actions |
| Actions must be pinned to a full commit SHA | A moved tag can't swap the code underneath you | A workflow using `@v4` is refused |
| `GITHUB_TOKEN` is read-only and can't approve PRs | Least privilege: workflows ask for more in their own `permissions:` block | Org settings > Actions > Workflow permissions |
| The allow-list covers every action this repo and its templates use | Without it, the policy could lock the platform out of its own workflows, or ship templates that can't run | Remove an entry: `checks` fails |
| Org settings are adopted, never destroyed | See provider quirks below | `terraform destroy` refuses to run |

## Classification (`custom_properties.tf`)

| Control | Why | How to check |
|---|---|---|
| Every repository carries `criticality`, `lifecycle`, `data-classification`, `contains-personal-data` and `technical-owner` | Risk-based rules need to know what each repository is. GitHub shows the values on the repository and filters by them (`props.criticality:tier-1`) | Repo > Settings > Custom properties; a repository missing one fails `terraform plan` |
| Only the org can change a repository's tier | Otherwise a repository admin could lower their own branch rules | Tested: the property must be editable by the org only |
| GitHub's own "required" flag stays off | It would force a default value onto repositories this code doesn't manage. Terraform requires the values instead, for every repository it manages | Tested |
| Switched-off properties are validated, never sent | A property can be built and tested before it is needed, then switched on in a one-line pull request | `terraform output switched_off`; tested |
| Unclassified repositories are reported | A repository made outside this code has no tier, so no branch rules | `platform-health` lists them daily |

## Branch rules by tier (`locals.tf`, `modules/repository`)

Each repository's `criticality` selects its tier's rules (`tier_policies` in
`platform.auto.tfvars`). A repository may ask for more than its tier, never for
less; to need less, change its tier.

| Rule | tier-1 | tier-2 | tier-3 | experimental |
|---|:-:|:-:|:-:|:-:|
| Pull request, 2 approvals, code owner review | Yes | Yes | Yes | No ruleset |
| No deletion, no force-push, squash merges only | Yes | Yes | Yes | |
| Approvals dismissed by new commits | Yes | Yes | No | |
| Conversations resolved before merging | Yes | Yes | No | |
| Linear history | Yes | No | No | |
| Required check `build-and-test` | Yes | Yes | No | |
| Signed commits | Off, waits on a signing-key policy | | | |
| Bypass | Org owners, through a pull request only | The same | The same | |

| Control | Why | How to check |
|---|---|---|
| Rules come from the tier, not from each repository | The same rules everywhere a tier applies; changing a tier changes every repository in it, in one reviewed pull request | Tested: every ruleset carries at least its tier's rules |
| A more critical tier is never weaker | Tier-1 must stay at least as strict as tier-2, and tier-2 as tier-3 | Tested on every pull request |
| The required check comes with the template | Repositories created from the template report `build-and-test` from their first pull request | `templates/repository-template/.github/workflows/ci.yml` |
| Enforcement per repository | New repositories are enforced from day one. An adopted repository can start `disabled` (or `evaluate`, on Enterprise Cloud) and be switched to `active` once it meets its tier | `ruleset_enforcement` in its entry; tested |

## Repository baseline (`modules/repository`)

| Control | Why | How to check |
|---|---|---|
| Secret scanning and push protection (public repositories) | Leaked secrets are blocked at push time | Repo > Settings > Advanced Security |
| Dependabot alerts and security updates | Known-vulnerable dependencies are flagged and patched | Repo > Security |
| Removing a repository archives it | Terraform never deletes code. The plan says "destroy"; the provider archives instead | `archive_on_destroy = true`, tested |
| Team access from one matrix, no standing admin | The same access everywhere; admin needs an explicit, reviewed exception | Grant a team admin: the tests fail |
| New repositories start from the template | CI, CODEOWNERS and Dependabot are there from the first commit | `template = "repository-template"`; [templates.md](templates.md) |

## Nothing is deleted

| What | Taking it out of config | Why |
|---|---|---|
| A repository | Archives it | Code is never lost |
| A team | Refused (`prevent_destroy`) | Deleting a team drops its members, its access and every CODEOWNERS rule naming it |
| A custom property | Refused (`prevent_destroy`) | Deleting a property wipes its value from every repository in the org |
| A template file | Left in GitHub, reported as Unmanaged | The publish script never deletes |
| Org settings | Refused (`prevent_destroy`) | See provider quirks below |

To stop managing a team or a property without deleting it, replace its entry
with a `removed` block, then delete it in GitHub on purpose if it should go:

```hcl
removed {
  from = github_team.this["old-team"]
  lifecycle {
    destroy = false
  }
}
```

## Detection

| Control | Why | How to check |
|---|---|---|
| Drift check every weekday, using the reader App | Changes made by hand don't go unnoticed | Setup step 9 |
| The drift issue opens, updates and closes itself | One open issue per environment, closed once fixed | Issues labelled `drift` |
| Health check every day, using the reader App | Covers what Terraform can't see: 2FA, member privileges, the Apps' permissions, this repository's own protections, failed runs | [health.md](health.md); issues labelled `platform-health` |
| Dependabot updates the actions and the provider | SHA pins and the provider don't go stale | Weekly Dependabot PRs, planned like any change |

## Quality gates (`tests/`, `.tflint.hcl`, `scripts/`)

- **Validation** in `variables.tf` rejects badly named repositories and teams,
  unknown teams, roles and properties, property values a property doesn't allow,
  missing required properties, a lowered tier, evaluate mode below Enterprise
  Cloud, a bad template, and anything the org's GitHub plan can't support, at
  `terraform plan`, in plain English.
- **Policy tests** in `tests/baseline.tftest.hcl` check every rule above against
  the real config of each environment, using a mocked provider, so they need no
  credentials. `tests/guardrails.tftest.hcl` feeds in one mistake per run and
  expects it to be rejected, and checks the tier, template and switched-off
  behaviour.
- **tflint** fails CI on any Terraform identifier that isn't snake_case.
- **The health check** has its own unit tests (`scripts/platform-health.test.js`),
  against fake GitHub responses.
- The suite was mutation-tested: 15 deliberate breakages when it was built, and
  20 more when classification and tiers were added (rules ignoring the tier, a
  tier editable by repository admins, switched-off properties sent, a lowered
  tier accepted, the wrong template). A test caught every one.

## Design decisions

- **HCP Terraform with Local execution.** HCP stores, versions and locks the state;
  Terraform runs in GitHub Actions. All the logic stays visible in the workflows,
  and GitHub credentials never leave GitHub. The free tier allows 500 managed
  resources; this lab manages about 55 per org.
- **The control repository is public.** GitHub Free offers Environments only on
  public repositories. The trade-off is that plans and config are publicly readable;
  there are no secrets in the repository or its logs. On a paid plan, make it private.
- **The control repository isn't managed by its own Terraform.** The bootstrap
  script sets it up, so this code can never delete or lock its own home. Terraform
  only grants the platform team access to it.
- **Every environment shares one config.** `platform.auto.tfvars` is shared;
  environment files hold only identity. Sandbox is a true rehearsal of prod.
- **Two Apps, not one App with narrower tokens.** The security boundary is the
  private key, not the token scope: any workflow holding a key that can mint a
  write token can write.
- **Tiers become one ruleset per repository** ([ADR 0003](adr/0003-classification-and-tiered-branch-rules.md)).
  Org rulesets that target a property need GitHub Team or Enterprise; per-repository
  rulesets work on every plan, and Terraform builds them from the tier.
- **Templates are published by an owner, not the pipeline** ([ADR 0004](adr/0004-templates-published-by-an-owner.md)),
  so neither App needs write access to file contents.
- **A health check beside the drift check** ([ADR 0005](adr/0005-health-check-beside-drift.md)):
  drift only sees what Terraform manages.
- **Billing and membership stay manual.** Finance owns billing, and people changes
  shouldn't wait on a pull request.
- **Apply re-plans.** The approver goes by the PR's plan; the apply job plans again
  (the state may have moved since) and applies exactly that saved plan.

## GitHub plan limits

| Feature | Free | Team | Enterprise Cloud |
|---|---|---|---|
| Rulesets on private repositories | no | yes | yes |
| Org rulesets (one ruleset for many repositories, e.g. by property) | no | yes | yes |
| Evaluate mode for rulesets (record what would be blocked) | no | no | yes |
| Custom properties | yes | yes | yes |
| Environments on private repositories | no | yes | yes |
| Required reviewers on private repositories | no | no | yes |
| Secret scanning on private repositories | no | paid add-on | paid add-on |
| Internal repositories | no | no | yes |

Set `github_plan` in each environment file; validation enforces these limits.

## Provider quirks handled (integrations/github v6.13)

Found by reading the provider's source code
(`resource_github_organization_settings.go`, `resource_github_repository.go`,
`resource_github_organization_custom_properties.go`).

| Quirk | What would happen | Handled by |
|---|---|---|
| Creating org settings sends only non-false booleans | The first apply leaves members able to create repositories until a second apply | The `import` block makes the first apply an update |
| Destroying org settings resets the org | The billing email is overwritten with `email@example.com` | `prevent_destroy = true` |
| Unmanaged org profile fields show as changes | A drift issue every day that no apply can fix | `ignore_changes` on the profile fields |
| Public repositories always report Advanced Security as on | A permanent diff on every public repository | `ignore_changes` on `advanced_security` |
| `vulnerability_alerts` on the repository resource is deprecated | Warnings now, removal later | The separate `github_repository_vulnerability_alerts` resource |
| A repository's template can't be changed after creation | A permanent diff on an existing repository given a template | `ignore_changes` on `template` |
| Destroying a custom property deletes it from GitHub | Every repository loses its value | `prevent_destroy = true`; retire it with a `removed` block |
| Mocked providers can't import | `terraform test` crashes | Tests set `adopt_organization_settings = false` |
| GitHub hides bypass actors and merge settings from the read-only App | Two changes per repository in every plan; drift never clears | `ignore_changes` on them ([ADR 0006](adr/0006-settings-the-reader-cannot-see.md)). A change by hand to them isn't detected |

## Manual by design

| Item | Why it isn't code | Checked by |
|---|---|---|
| Require two-factor authentication (both orgs) | GitHub has no API for it | `platform-health`, daily |
| Members can't delete, transfer or change the visibility of repositories | The API can read these but not set them | `platform-health`, daily |
| Deploy keys off, fork PR approval | Not in the Terraform provider | `platform-health`, daily |
| Team membership and org owners | People changes shouldn't wait on a pull request | |
| Publishing the templates | Keeps file write access out of the pipeline's Apps | `Publish-Templates.ps1` dry run |
| Billing | Owned by whoever pays | |
| Copilot seats | A licensing decision, not configuration | |
| Creating the GitHub Apps and changing their permissions | GitHub requires the browser flow | `platform-health`, daily |
| HCP organization and token | One-time account setup | |
