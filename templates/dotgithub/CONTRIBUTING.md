# Contributing

How we work in {{ORGANIZATION}}. A repository can add its own
`CONTRIBUTING.md` for anything specific to it, such as how to build and test.

## Branches

* `main` is the only long-lived branch, and it is always releasable.
* Make each change on a short-lived branch, merged within a few days.
* Nobody pushes to `main` directly: every change arrives by pull request.

## Pull requests

* **Small and single-purpose.** One logical change a reviewer can follow in one
  sitting.
* **Reviews.** The rules depend on the repository's criticality tier (its
  `criticality` custom property). Most tiers need two approvals, one of them
  from the code owners in `.github/CODEOWNERS`, who GitHub asks automatically.
  Nobody can approve their own pull request.
* **Checks must pass.** Tier-1 and tier-2 repositories need the `build-and-test`
  check. Don't merge around a failing check: fix it, or ask the owners.
* **Squash merge only.** Each pull request lands as one commit on `main`, so
  every change traces back to one reviewed pull request.
* Resolve review conversations before merging.

## Commits

* Say what changed and why in the first line, in about 70 characters.
* Commits made in the web editor carry your sign-off automatically.
* Never commit secrets, keys, certificates or personal data. See the
  [security policy](SECURITY.md).

## Getting help

See [SUPPORT.md](SUPPORT.md).
