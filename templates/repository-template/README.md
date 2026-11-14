# Repository name

One or two sentences: what this repository holds, and who uses it.

| | |
|---|---|
| **Code owners** | `@{{ORGANIZATION}}/{{CODE_OWNERS_TEAM}}`, in [`.github/CODEOWNERS`](.github/CODEOWNERS). Their review is part of every merge |
| **Branch rules** | Set by this repository's `criticality` tier (Settings > Custom properties), from [{{PLATFORM_REPOSITORY}}](https://github.com/{{PLATFORM_REPOSITORY}}) |
| **Security** | Report vulnerabilities as the organisation's security policy says, never in an issue |

## Getting started

<!-- What someone needs installed, and how to get a working copy running. -->

## Build and test

<!-- The commands. CI runs the same ones: .github/workflows/ci.yml -->

## Deploy

<!-- Where this runs, and how a change reaches each environment. -->

## After creating this repository

- [ ] Replace the placeholders in this README
- [ ] Replace the "Build and test" step in `.github/workflows/ci.yml`, keeping the job name `build-and-test`
- [ ] Add this repository's package ecosystems to `.github/dependabot.yml`
- [ ] Check its description, topics and custom properties
