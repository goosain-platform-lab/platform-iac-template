# Templates

Two repositories give every new repository a good start. Their files live
in [`templates/`](../templates), are changed by pull request like everything
else, and reach GitHub when an org owner publishes them.

| Folder | Published to | What it gives |
|---|---|---|
| `templates/repository-template/` | `repository-template`, a template repository Terraform creates | CI that reports the `build-and-test` check, CODEOWNERS naming the lead developers, Dependabot for Actions, a `.gitignore` |
| `templates/dotgithub/` | the org's `.github` repository | The default security policy, contributing guide, support page, issue forms, pull request template and starter workflow, for every repository without its own. **Switched off** until its two contacts are filled in |

## Why a script and not the pipeline

The pipeline's Apps manage settings, not file contents. Publishing files from
the pipeline would need write access to the contents of every repository in
both orgs, for a change made a few times a year. So an owner publishes with
[`scripts/Publish-Templates.ps1`](../scripts/Publish-Templates.ps1), from their
own machine, and every change still arrives as a reviewed pull request.

## Publish

From the repository root, on `main`, up to date (`git switch main; git pull`),
with `gh` signed in as an owner. Publishing workflow files needs the
`workflow` scope, once: `gh auth refresh --scopes workflow`.

```powershell
.\scripts\Publish-Templates.ps1 -Environment sandbox          # read-only: shows what would change
.\scripts\Publish-Templates.ps1 -Environment sandbox -Apply   # opens one pull request per repository
```

Merge the pull request it opens in the sandbox org, then do the same with
`-Environment prod`. Production is refused until the sandbox already holds the
same files.

| Result | Meaning |
|---|---|
| Create, Update | Proposed in the pull request |
| No change | Already matches `templates/` |
| Unmanaged | A file in GitHub that `templates/` doesn't hold, such as the org profile `profile/README.md`. Reported, never removed |
| Off | Switched off in `templates.json`: checked, never published |
| Blocked | Nothing is published to that repository. The line says what to do |

The script never pushes to a default branch and never deletes a file. Publish
again after merging: every file should show **No change**.

## Placeholders

Text such as `{{ORGANIZATION}}` is filled in when publishing:

| Placeholder | Becomes |
|---|---|
| `{{ORGANIZATION}}` | The environment's org, from `environments/<environment>.tfvars` |
| `{{PLATFORM_REPOSITORY}}` | This repository, as `owner/name` |
| Anything else, e.g. `{{CODE_OWNERS_TEAM}}` | Its value under `values` in [`templates/templates.json`](../templates/templates.json) |

A placeholder without a value blocks publishing, so one can never reach GitHub.
GitHub expressions such as `${{ github.ref }}` are left alone.

## Switch on the org defaults (`.github`)

The security policy has to name a real way to report a vulnerability, so
`.github` is switched off until you decide it:

1. In `templates/templates.json`, fill in `SECURITY_CONTACT` (where
   vulnerabilities are reported privately) and `SUPPORT_CONTACT` (where people
   ask for help and new repositories). They are published in public
   repositories: use a shared mailbox or a link, not a personal address.
2. Change `.github`'s `"enabled": false` to `true`, in the same pull request.
3. After merging, create the repository in any org that lacks one
   (`gh repo create <org>/.github --public`), then publish, sandbox first.

## Create a repository from the template

The template must be published first; a repository created from an empty
template starts with only its README. Then add the repository with `template`
set, in `platform.auto.tfvars`:

```hcl
claims-api = {
  description = "Claims processing API"
  topics      = ["claims", "dotnet"]
  template    = "repository-template"
  properties = {
    criticality            = "tier-2"
    data-classification    = "internal"
    contains-personal-data = "yes"
    technical-owner        = "lead-developers"
  }
}
```

Terraform creates it as a copy of the template's files, with its tier's branch
rules from the first commit. `template` only matters when the repository is
created: setting it on an existing repository changes nothing.

Creating from a template needs the writer App's **Contents: Read-only**
permission (see [setup](setup.md#4-two-github-apps-reader-and-writer)).

## Change a template

1. Edit the files under `templates/` and open a pull request. The checks make
   sure every action in a template workflow is SHA-pinned and allowed, and that
   the org's starter workflow still matches the template's CI.
2. After merging, publish to the sandbox, merge its pull request, then publish
   to production.

Don't edit `repository-template` or `.github` directly in GitHub: the next
publish proposes undoing it.

## When something is wrong

| You see | Do this |
|---|---|
| Blocked: no value for `X` | Fill `X` in `templates/templates.json`, or keep the repository switched off |
| Blocked: `<org>/repository-template` does not exist | Merge the change that adds it to `platform.auto.tfvars` and let the apply finish |
| Blocked: an earlier publish is still open | Merge or close that pull request, then publish again |
| STOPPED: publish only what is merged | Switch to `main` and pull: only merged templates are published |
| `refusing to allow ... to create or update workflow` | `gh auth refresh --scopes workflow`, then publish again |
| A file shows Update after merging | It was edited in GitHub. Publishing again proposes `templates/`'s version |
