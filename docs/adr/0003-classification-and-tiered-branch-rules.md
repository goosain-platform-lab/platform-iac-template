# ADR 0003: Classification by custom properties, branch rules by tier

**Status:** Accepted

## Context

One set of branch rules for every repository is too strict for experiments and
too loose for critical systems. Rules should follow what a repository is, and
what a repository is should be recorded where GitHub and people can see it.

## Options considered

| Option | For | Against |
|---|---|---|
| Rules set repository by repository | Fully flexible | Drifts apart; nobody can say which repositories get which rules |
| **Custom properties, with a ruleset per repository built from its tier** *(chosen)* | Works on every GitHub plan; the tier is visible on the repository; Terraform checks every repository gets its tier's rules | One ruleset per repository instead of one per tier |
| Org rulesets that target a property | One ruleset per tier; applies to repositories made outside the code too | Needs GitHub Team or Enterprise; evaluate mode needs Enterprise |

## Decision

- Five properties every managed repository must carry: `criticality`,
  `lifecycle`, `data-classification`, `contains-personal-data` and
  `technical-owner`. Only the org can change `criticality`, so no repository can
  lower its own rules.
- `criticality` is the tier: `tier-1`, `tier-2`, `tier-3` or `experimental`.
  `tier_policies` says what each tier requires; the more critical tier is
  never weaker, and tests enforce it.
- A repository may ask for more than its tier (approvals, extra checks), never
  for less: to need less, change its tier.
- Tier-1 and tier-2 require the `build-and-test` check, which the template's CI
  reports, so a repository created from the template meets its tier from its
  first pull request.
- Signed commits are built and switched off until there is a signing-key policy.
- A property can be configured but switched off: validated and tested, never
  sent to GitHub.

## Consequences

- A repository created outside this code has no tier and no rules. Members
  can't create repositories, and the health check lists any that appear.
- On a Team or Enterprise plan, the per-repository rulesets could become org
  rulesets targeting `criticality`. The tier policies would not change.
- An existing repository adopted into the code can start with its ruleset
  `disabled` and be switched to `active` once it meets its tier.
