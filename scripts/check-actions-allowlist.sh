#!/usr/bin/env bash
# Stops the platform locking itself out of its own workflows.
#
# The org's Actions policy (platform.auto.tfvars, actions_policy) only lets
# GitHub-owned actions plus an explicit allow-list run, and it requires every
# action to be pinned to a full commit SHA. This repository's workflows run
# under that same policy. A workflow using an action the policy blocks would
# stop working after the next apply, including the workflow you'd need to fix
# it, so this check fails the pull request first.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="$repo_root/platform.auto.tfvars"
[[ -f "$config" ]] || { echo "::error::$config not found"; exit 1; }

mapfile -t refs < <(
  grep -rhoE '^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*[^[:space:]#]+' \
    "$repo_root/.github/workflows" "$repo_root/.github/actions" |
    sed -E "s/^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*//; s/^[\"']//; s/[\"']\$//" |
    grep -v '^\./' |
    sort -u
)
((${#refs[@]} > 0)) || { echo "::error::No 'uses:' lines found under .github; the scan itself is broken."; exit 1; }

github_owned_allowed=false
if grep -qE '^[[:space:]]*github_owned_allowed[[:space:]]*=[[:space:]]*true' "$config"; then
  github_owned_allowed=true
fi

errors=0
for ref in "${refs[@]}"; do
  action="${ref%@*}"
  pin="${ref##*@}"
  repo="$(cut -d/ -f1,2 <<<"$action")"
  owner="${repo%%/*}"

  if [[ "$ref" != *@* || ! "$pin" =~ ^[0-9a-f]{40}$ ]]; then
    echo "::error::$ref is not pinned to a full commit SHA, which the org policy requires."
    errors=$((errors + 1))
  fi

  if [[ "$owner" == "actions" || "$owner" == "github" ]]; then
    if [[ "$github_owned_allowed" != true ]]; then
      echo "::error::$repo is GitHub-owned, but github_owned_allowed is not true in platform.auto.tfvars."
      errors=$((errors + 1))
    fi
  elif ! grep -qF "\"$repo@*\"" "$config"; then
    echo "::error::$repo is used under .github but is not allowed by the org. Add \"$repo@*\" to actions_policy.patterns_allowed in platform.auto.tfvars."
    errors=$((errors + 1))
  fi
done

if ((errors > 0)); then
  echo "$errors problem(s) found."
  exit 1
fi
echo "OK: ${#refs[@]} action reference(s), all SHA-pinned and allowed by the org policy."
