# Organisation defaults for {{ORGANIZATION}}

GitHub uses the files in this repository for every repository in
{{ORGANIZATION}} that has no file of the same kind.

| File | Used for |
|---|---|
| [`SECURITY.md`](SECURITY.md) | How to report a vulnerability. Shown on every repository's Security tab |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How we work: branches, pull requests, reviews |
| [`SUPPORT.md`](SUPPORT.md) | Where to get help |
| [`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE/) | The bug report and feature request forms |
| [`.github/pull_request_template.md`](.github/pull_request_template.md) | The pull request description |
| [`workflow-templates/`](workflow-templates/) | The starter CI offered under Actions > New workflow |

A repository with its own file of the same kind uses that instead.

## Changing these files

Don't edit them here. They are published from `templates/dotgithub/` in
[{{PLATFORM_REPOSITORY}}](https://github.com/{{PLATFORM_REPOSITORY}}): change them
there by pull request, and the next publish proposes the change here, also as a
pull request.
