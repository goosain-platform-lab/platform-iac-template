# ADR 0005: A health check beside the drift check

**Status:** Accepted

## Context

The drift check proves GitHub matches everything Terraform manages. It can't see
what Terraform doesn't manage: two-factor authentication and member privileges
(no API to set them), settings the provider lacks, whether the Apps still hold
their permissions, the platform repository's own protections, or a failed apply.
Any of these can go wrong quietly.

## Options considered

| Option | For | Against |
|---|---|---|
| Rely on the drift check | Nothing new to build | The gaps above stay invisible |
| Manage the missing settings through scripts in the apply | One place | Two engines changing the same org; some settings have no API at all |
| **A separate read-only check with its own issue** *(chosen)* | Covers the gaps without changing anything; one issue to watch | Another workflow and its expectations to maintain |

## Decision

- `platform-health` runs every morning and on demand. It reads as the reader
  App and with its own read-only token, and writes only its issue.
- What it expects is in `scripts/platform-health.json`. Changing that file
  changes what is reported, never what is in GitHub.
- Results are Pass, N/A, Unknown, Warn or Fail. **Unknown is never a pass**: a
  check it can't read keeps an open issue open. Fail turns the run red.
- One `platform-health` issue, rewritten every run, closed by itself once
  everything passes and could be read.
- The script has unit tests against fake GitHub responses, run on every pull
  request.

## Consequences

- A missed App permission update, which makes the next apply fail, shows up in
  the next morning's report.
- Every manual setting in docs/controls.md now has something checking it.
