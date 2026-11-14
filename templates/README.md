# Templates

The files behind two repositories that every org gets. Edit them here, by pull
request, never in the org: [`scripts/Publish-Templates.ps1`](../scripts/Publish-Templates.ps1)
publishes them, and proposes any later difference as a pull request in the
target repository.

| Folder | Published to |
|---|---|
| [`repository-template/`](repository-template/) | `repository-template`: CI reporting `build-and-test`, CODEOWNERS, Dependabot, `.gitignore` |
| [`dotgithub/`](dotgithub/) | the org's `.github` repository: security policy, contributing guide, support page, issue forms, pull request template, starter workflow |

[`templates.json`](templates.json) says which repositories are switched on and
holds the values for `{{PLACEHOLDERS}}`. Nothing here runs in this repository:
GitHub only reads `.github/` at a repository's root.

How to publish, switch on `.github`, and create a repository from the template:
[docs/templates.md](../docs/templates.md).
