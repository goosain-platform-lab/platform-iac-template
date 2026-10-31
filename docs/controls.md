# Controls

What each control does, where it lives, why it exists and how to check it.

## Change control

| Control | Where | Why | How to check |
|---|---|---|---|
| Changes reach main only by pull request | Control repo ruleset `default-branch-protection` (bootstrap step 6) | Every change is reviewed and recorded | `git push origin main` is rejected |
| Every PR is planned against both environments | `terraform-plan.yml` | The reviewer sees the exact effect on sandbox and prod before merging | One plan comment per environment |
| Static checks run before any plan | `checks` job: fmt, validate, tflint, tests, allow-list | Mistakes fail before a single API call | Break the formatting: `checks` fails |
| Sandbox first, prod second | `terraform-apply.yml`: `apply-prod` needs `apply-sandbox` | A change that breaks sandbox never reaches prod | A failed sandbox apply: prod never starts |
| Prod waits for a person | `prod` Environment, required reviewer | Human approval before prod changes | The run pauses at "Waiting for review" |
| One apply at a time | `concurrency: terraform-apply` plus the HCP state lock | Two applies can't race on the same org | A second run queues behind the first |

## Credentials

| Control | Where | Why | How to check |
|---|---|---|---|
| No personal access tokens | Two GitHub Apps; tokens minted per job in `terraform-setup` | Tokens last one hour and belong to an App, not a person | The token step in any job log |
| Pull requests and drift checks are read-only | Reader App, read-only permissions | No pull request, even a malicious one, can change GitHub | The reader App's permissions page |
| The writer key is reachable only from main | `GH_APP_WRITER_PRIVATE_KEY` is an Environment secret; both Environments accept main only | Workflow code on a PR branch can't read it | Environment settings > Deployment branches |
| HCP team token with an expiry | `TF_API_TOKEN` | Organization tokens can't run Terraform; user tokens are tied to a person | HCP > Settings > API tokens |
| The checkout token isn't left behind | `persist-credentials: false` on every checkout | Later steps can't reuse it | The workflow files |
| Secrets never enter git or logs | `*.pem` ignored; tfvars hold config only; `billing_email` is `sensitive`; push protection on this repo | Nothing secret is committed or printed | Push a fake key: push protection blocks it |

## Organization baseline (`organization.tf`, `actions.tf`)

| Control | Why | How to check |
|---|---|---|
| Members can't create repositories or Pages | Every repository goes through this code and gets the baseline | Org settings > Member privileges; also tested |
| Base permission `read` | On public repositories it changes nothing. On a paid plan with private repositories, set `none` so access comes only from teams | Org settings > Member privileges |
| Only GitHub-owned and allow-listed actions run | A third-party action is someone else's code running with your secrets | Org settings > Actions |
| Actions must be pinned to a full commit SHA | A moved tag can't swap the code underneath you | A workflow using `@v4` is refused |
| `GITHUB_TOKEN` is read-only and can't approve PRs | Least privilege: workflows ask for more in their own `permissions:` block | Org settings > Actions > Workflow permissions |
| The allow-list covers every action this repo uses | Without it, the policy could lock the platform out of its own workflows | Remove an entry: `checks` fails |
| Org settings are adopted, never destroyed | See provider quirks below | `terraform destroy` refuses to run |

## Repository baseline (`modules/repository`)

| Control | Why | How to check |
|---|---|---|
| Default branch needs a PR, 1 approval and resolved threads; new commits dismiss old approvals | Four eyes on every change | Repo > Settings > Rules |
| Squash only, linear history, no force-push or branch deletion | History stays readable and can't be rewritten | The merge button offers only squash |
| Only org owners can bypass, and only through a PR | A solo maintainer can still merge; nobody pushes straight to main | Push to main as an owner: rejected |
| Secret scanning and push protection (public repositories) | Leaked secrets are blocked at push time | Repo > Settings > Advanced Security |
| Dependabot alerts and security updates | Known-vulnerable dependencies are flagged and patched | Repo > Security |
| Removing a repository archives it | Terraform never deletes code. The plan says "destroy"; the provider archives instead | `archive_on_destroy = true`, tested |
| Team access from one matrix, no standing admin | The same access everywhere; admin needs an explicit, reviewed exception | Grant a team admin: the tests fail |

## Detection

| Control | Why | How to check |
|---|---|---|
| Drift check every weekday, using the reader App | Changes made by hand don't go unnoticed | Setup step 9 |
| The drift issue opens, updates and closes itself | One open issue per environment, closed once fixed | Issues labelled `drift` |
| Dependabot updates the actions and the provider | SHA pins and the provider don't go stale | Weekly Dependabot PRs, planned like any change |

## Quality gates (`tests/`, `.tflint.hcl`)

- **Validation** in `variables.tf` rejects badly named repositories and teams,
  unknown teams or roles, placeholder emails, and anything the org's GitHub plan
  can't support, at `terraform plan`, in plain English.
- **Policy tests** in `tests/baseline.tftest.hcl` check every rule above against the
  real config of each environment, using a mocked provider, so they need no
  credentials. `tests/guardrails.tftest.hcl` feeds in one mistake per run and
  expects it to be rejected.
- **tflint** fails CI on any Terraform identifier that isn't snake_case.
- The suite was mutation-tested when built: 15 deliberate breakages (protections
  switched off, validation rules disabled, admin granted) each made a test fail.

## Design decisions

- **HCP Terraform with Local execution.** HCP stores, versions and locks the state;
  Terraform runs in GitHub Actions. All the logic stays visible in the workflows,
  and GitHub credentials never leave GitHub. The free tier allows 500 managed
  resources; this lab manages about 50.
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
- **Billing and membership stay manual.** Finance owns billing, and people changes
  shouldn't wait on a pull request.
- **Apply re-plans.** The approver goes by the PR's plan; the apply job plans again
  (the state may have moved since) and applies exactly that saved plan.

## GitHub plan limits

| Feature | Free | Team | Enterprise Cloud |
|---|---|---|---|
| Rulesets on private repositories | no | yes | yes |
| Environments on private repositories | no | yes | yes |
| Required reviewers on private repositories | no | no | yes |
| Secret scanning on private repositories | no | paid add-on | paid add-on |
| Internal repositories | no | no | yes |

Set `github_plan` in each environment file; validation enforces these limits.

## Provider quirks handled (integrations/github v6.13)

Found by reading the provider's source code
(`resource_github_organization_settings.go`, `resource_github_repository.go`).

| Quirk | What would happen | Handled by |
|---|---|---|
| Creating org settings sends only non-false booleans | The first apply leaves members able to create repositories until a second apply | The `import` block makes the first apply an update |
| Destroying org settings resets the org | The billing email is overwritten with `email@example.com` | `prevent_destroy = true` |
| Unmanaged org profile fields show as changes | A drift issue every day that no apply can fix | `ignore_changes` on the profile fields |
| Public repositories always report Advanced Security as on | A permanent diff on every public repository | `ignore_changes` on `advanced_security` |
| `vulnerability_alerts` on the repository resource is deprecated | Warnings now, removal later | The separate `github_repository_vulnerability_alerts` resource |
| Mocked providers can't import | `terraform test` crashes | Tests set `adopt_organization_settings = false` |

## Manual by design

| Item | Why it isn't code |
|---|---|
| Require two-factor authentication (both orgs) | GitHub has no API for it |
| Team membership and org owners | People changes shouldn't wait on a pull request |
| Billing | Owned by whoever pays |
| Copilot seats | A licensing decision, not configuration |
| Creating the GitHub Apps | GitHub requires the browser flow |
| HCP organization and token | One-time account setup |
