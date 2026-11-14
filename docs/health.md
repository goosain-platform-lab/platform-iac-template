# Health check

Two scheduled checks watch the platform. They answer different questions.

| | terraform-drift | platform-health |
|---|---|---|
| Asks | Does GitHub still match the code? | Is everything the code relies on still in place? |
| Covers | Everything Terraform manages | What Terraform can't see (below) |
| Runs | Weekdays 06:17 SAST | Daily 06:41 SAST, and on demand |
| Raises | One `drift` issue per environment | One `platform-health` issue |

Both only read GitHub. Their one write is their own issue, which opens when
something needs attention, is rewritten every run, and closes itself once
everything passes.

## What platform-health checks

| Where | Check | Wrong means |
|---|---|---|
| Each org | Two-factor authentication is required | **Fail.** GitHub has no API to set it, so Terraform can't |
| | Members can't delete, transfer or change the visibility of repositories | Warn. The API can read these but not set them |
| | Deploy keys are off; fork pull request workflows wait for approval; no self-hosted runners | Warn. Settings the Terraform provider doesn't manage. N/A where the org's plan doesn't offer one |
| | Both Apps are installed on all repositories, with exactly the permissions the pipeline needs | **Fail** if one is missing or lacks a permission (a missed permission update shows up here). Warn if it holds more than it needs |
| | Every repository has a `criticality` tier | Warn, listing the repositories. Without a tier a repository gets no branch rules. Archived repositories, `.github` and this repository are not counted |
| This repository | Environments `sandbox` and `prod` deploy from `main` only, and `prod` needs an approval | **Fail** |
| | `main` takes pull requests only, with code owner review and the `checks`, `plan (sandbox)` and `plan (prod)` checks | **Fail** |
| | CODEOWNERS has no errors | **Fail.** GitHub silently skips an owner it can't use |
| | The last `terraform-apply` and `terraform-drift` runs on `main` succeeded | **Fail.** Warn if a prod apply has waited for approval for more than 24 hours |
| | No `drift` issue is open | Warn |

What each check expects is in
[`scripts/platform-health.json`](../scripts/platform-health.json). Changing it
changes what is *reported*, never what is in GitHub.

## What a result means

| Result | Meaning | Run | Issue |
|---|---|---|---|
| Pass | As expected | Green | Closes, once everything passes and could be read |
| N/A | Not offered for that org | Green | Doesn't count against closing |
| Unknown | Couldn't be read, usually a missing App permission. Never a pass | Green | Not opened for it. One already open stays open |
| Warn | Worth a look | Green, with a warning | Opened or rewritten |
| Fail | Something is broken | **Red** | Opened or rewritten |

## Tokens

The org checks run as the **reader App**, one token per org, the same
permissions plan and drift use. The checks on this repository use the
workflow's own token, with read access to contents and Actions. Only the issue
is written, with `issues: write`. The writer App's key is never used: its name
is worked out from the naming convention (`<owner>-platform-reader` becomes
`<owner>-platform-writer`).

## Run it now

**Actions > platform-health > Run workflow.** The run summary shows the full
report, passes included.

## Fixing what it finds

| It says | Do this |
|---|---|
| `two_factor_requirement_enabled`: false | Org Settings > Authentication security > Require two-factor authentication. Members without 2FA are removed, so check first |
| A member privilege is true | Org Settings > Member privileges, as the detail says |
| An App is missing a permission | Change it on the App's settings page, then **accept the update in each org**: Settings > GitHub Apps > the App. Until then the App works with its old permissions |
| An App is not installed, or only on selected repositories | Install it on that org with **All repositories** |
| A repository has no `criticality` | Add it to `platform.auto.tfvars` with its properties, or archive it if nobody needs it |
| An environment or the rules on `main` are wrong | Re-run `scripts/Initialize-ControlRepo.ps1` with `-Apply`: it puts them back |
| Unknown, HTTP 403 | The reader App lacks a permission the check needs. Compare it with [setup](setup.md#4-two-github-apps-reader-and-writer) |
