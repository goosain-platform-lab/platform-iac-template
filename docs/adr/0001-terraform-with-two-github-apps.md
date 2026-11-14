# ADR 0001: Terraform, with HCP state and two GitHub Apps

**Status:** Accepted

## Context

GitHub org settings, teams and repository protections were set by hand. Every
change needs to be reviewed, repeatable, and visible as a diff before it
happens, and a change made by hand has to be noticed.

## Options considered

| Option | For | Against |
|---|---|---|
| **Terraform with the `integrations/github` provider** *(chosen)* | Plan and apply built in; drift is a plan with changes; widely known | Not every GitHub setting has a resource; needs somewhere to keep state |
| A script engine reading JSON | Can call any API, including ones the provider lacks | The plan, state and drift logic all have to be written and maintained |
| A GitHub App that enforces settings continuously | No pipeline to run | Needs hosting and patching; weaker on org-level settings |

## Decision

- Terraform, pinned to one version (`.terraform-version`), with the provider
  pinned by `.terraform.lock.hcl`.
- State in HCP Terraform's free tier with **Local** execution: HCP stores and
  locks the state, GitHub Actions runs the plans, so the logic stays visible in
  the workflows and GitHub credentials never leave GitHub.
- Two GitHub Apps instead of personal tokens: a **reader** for plans, drift and
  health, and a **writer** whose key is reachable only from `main`, through the
  Environments.

## Consequences

- Settings the provider can't manage are checked instead of set
  ([ADR 0005](0005-health-check-beside-drift.md)).
- Provider quirks are handled in code, each with a comment (docs/controls.md).
- Anyone who knows Terraform can read the platform: the config is the documentation.
