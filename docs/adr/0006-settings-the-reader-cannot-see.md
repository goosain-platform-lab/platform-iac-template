# ADR 0006: Settings the read-only App can't see

**Status:** Accepted

## Context

Plans, drift and health run as the reader App, which can only read
([ADR 0001](0001-terraform-with-two-github-apps.md)). GitHub hides some settings
from a caller that can't change them:

- a ruleset's bypass actors are returned only to a caller with write access to
  the ruleset;
- a repository's merge settings (merge methods, update branch, delete branch on
  merge, commit titles and messages) come back as off.

So every plan showed two changes per repository that weren't real, the drift
issues never closed, and a merge setting changed by hand was never caught.

## Options considered

| Option | For | Against |
|---|---|---|
| Accept the noise | Nothing to change | Drift is always "detected", so real drift is lost in it |
| Give the reader Administration: write | Every setting visible | The read-only App can change repositories; the two-App split loses its point |
| Plan and check drift as the writer | Every setting visible | The writer's key leaves the approved `main` deployments |
| **Stop comparing what the reader can't see** *(chosen)* | Plans and drift show only real changes; the reader stays read-only | A change by hand to those settings isn't detected |

## Decision

- `ignore_changes` on the ruleset's `bypass_actors` and on the repository's merge
  settings (`modules/repository/main.tf`). They are set when the repository and
  ruleset are created, and not compared after.
- Squash-only stays enforced: the ruleset's `allowed_merge_methods`, which the
  reader can see, blocks any other merge whatever the repository setting says.

## Consequences

- A bypass actor added by hand isn't detected by drift or health. Review a
  ruleset's bypass list in the UI after an incident or a change of owners.
- Changing the bypass or merge settings in code affects new repositories only.
  To change existing ones, edit them by hand or recreate the ruleset.
- The drift demonstration (setup step 9) uses a setting the reader can see.
