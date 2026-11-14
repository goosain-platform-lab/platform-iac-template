# ADR 0004: Templates published by an owner, not the pipeline

**Status:** Accepted

## Context

New repositories should start with CI, CODEOWNERS and Dependabot, and every
repository should inherit a security policy and contributing guide. These are
files, not settings. The pipeline's Apps manage settings only.

## Options considered

| Option | For | Against |
|---|---|---|
| Manage the files with Terraform (`github_repository_file`) | Planned and applied like everything else | Both Apps need write access to file contents in every repository, for a change made a few times a year |
| **Keep the files in this repository; an owner publishes them as pull requests** *(chosen)* | No new App permissions; every change is still reviewed twice: here, and as a pull request in the target repository | A person has to run the publish |

## Decision

- `templates/` holds the files for `repository-template` and the org's `.github`
  repository. `templates/templates.json` says which repositories get them and
  the values for their placeholders.
- `scripts/Publish-Templates.ps1` compares them with GitHub and opens one pull
  request per repository. It is read-only without `-Apply`, publishes only what
  is merged on `main`, refuses production until the sandbox holds the same
  files, and never deletes a file.
- A repository whose values aren't decided yet is switched off: checked, never
  published. `.github` waits on a security contact.
- Terraform creates `repository-template` itself, and creates new repositories
  from it. The writer App only needs to read its contents.

## Consequences

- The template's CI is checked like the platform's own workflows: every action
  SHA-pinned and allowed by the org's policy.
- Repositories created from the template keep their own copies; changing the
  template does not change them.
