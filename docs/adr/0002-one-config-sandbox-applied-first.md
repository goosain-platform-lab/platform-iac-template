# ADR 0002: One shared config, applied to the sandbox first

**Status:** Accepted

## Context

Every change should run in a sandbox org before production. A rule people have
to remember is the first thing skipped under time pressure, so the order has to
be built into the pipeline.

## Options considered

| Option | For | Against |
|---|---|---|
| **One config for both orgs, applied in order** *(chosen)* | The sandbox is an exact rehearsal; one pull request per change; nothing to copy between folders | Both orgs get the same config: a production-only setting needs a variable |
| A folder per org, with a gate that checks production matches the sandbox | Each org's config is explicit; a change can sit in the sandbox for a while | Two pull requests per change, and config duplicated by design |
| A config per org, kept in step by hand | Simple | Nothing stops a production change that was never tested |

## Decision

- `platform.auto.tfvars` is shared. `environments/<environment>.tfvars` holds
  only which org and which GitHub plan.
- Every pull request plans both orgs and posts both plans.
- After a merge, `apply-prod` needs `apply-sandbox`: a change that fails in the
  sandbox never starts in production. Production then waits for a platform
  owner's approval on the `prod` Environment.

## Consequences

- To soak a change in the sandbox before production, merge it and leave the prod
  approval waiting. The health check warns if it waits more than a day.
- An environment-specific difference is a variable in `environments/`, which is
  visible and reviewed, never a second copy of the config.
