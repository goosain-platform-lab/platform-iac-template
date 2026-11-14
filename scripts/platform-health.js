'use strict';
// The daily platform health check (.github/workflows/platform-health.yml).
//
// terraform-drift asks "does GitHub still match the code?". This asks what
// Terraform cannot see: org settings the provider cannot manage, whether the
// Apps still hold the permissions the pipeline needs, the platform
// repository's own protections, and whether the last runs worked.
//
// It only reads GitHub. Its one write is the platform-health issue, opened
// when something needs attention and closed by itself once everything passes.
// Expectations live in scripts/platform-health.json. Unit tests:
//   node --test scripts/platform-health.test.js

const fs = require('fs');
const path = require('path');

const STATUS_ORDER = ['fail', 'warn', 'unknown', 'skip', 'pass'];
const STATUS_LABEL = { fail: 'FAIL', warn: 'WARN', unknown: 'UNKNOWN', skip: 'N/A', pass: 'PASS' };
const LEVEL = { read: 1, write: 2, admin: 3 };
const ISSUE_TITLE = 'Platform health';
const ISSUE_LABEL = 'platform-health';

function result(scope, check, status, detail) {
  return { scope, check, status, detail };
}

function explain(error) {
  if (error && error.status === 403) return 'GitHub refused (HTTP 403): the token lacks a permission this check needs.';
  if (error && error.status === 404) return 'Not found (HTTP 404): not visible to this token, or not offered on this plan.';
  return `Could not be read: ${error && error.message ? error.message : error}`;
}

// Runs one check. Anything it cannot read is Unknown, never a pass.
async function guarded(scope, check, run) {
  try {
    const out = await run();
    return Array.isArray(out) ? out : [out];
  } catch (error) {
    return [result(scope, check, 'unknown', explain(error))];
  }
}

const show = (value) => JSON.stringify(value);

// --- Each org -----------------------------------------------------------------

async function checkOrganizationSettings(env, expected) {
  const { data } = await env.client.request('GET /orgs/{org}', { org: env.org });
  return expected.organization.settings.map((setting) => {
    const actual = data[setting.field];
    if (actual === undefined || actual === null) {
      return setting.optional
        ? result(env.scope, setting.field, 'skip', 'Not returned for this org: its plan does not offer the setting.')
        : result(env.scope, setting.field, 'unknown', 'Not returned: the reader App needs Organization administration (read).');
    }
    if (actual === setting.expected) return result(env.scope, setting.field, 'pass', show(actual));
    return result(env.scope, setting.field, setting.severity, `${show(actual)}, expected ${show(setting.expected)}. ${setting.fix}`);
  });
}

async function checkActionsSetting(env, setting) {
  let data;
  try {
    ({ data } = await env.client.request(`GET ${setting.path}`, { org: env.org }));
  } catch (error) {
    if (setting.optional && error && error.status === 404) {
      return result(env.scope, setting.field, 'skip', 'Not offered for this org.');
    }
    throw error;
  }
  const actual = data[setting.field];
  if (actual === setting.expected) return result(env.scope, setting.field, 'pass', show(actual));
  return result(env.scope, setting.field, setting.severity, `${show(actual)}, expected ${show(setting.expected)}. ${setting.fix}`);
}

// The writer App is never given to this workflow, so its name comes from the
// naming convention: <owner>-platform-reader and <owner>-platform-writer.
function appSlugs(readerSlug) {
  return {
    reader: readerSlug || null,
    writer: readerSlug && readerSlug.endsWith('-reader') ? readerSlug.replace(/-reader$/, '-writer') : null,
  };
}

function comparePermissions(actual, wanted) {
  const missing = [];
  const extra = [];
  for (const [name, level] of Object.entries(wanted)) {
    const has = actual[name];
    if ((LEVEL[has] || 0) < LEVEL[level]) missing.push(`${name} (needs ${level}, has ${has || 'none'})`);
  }
  for (const [name, has] of Object.entries(actual)) {
    if (!(name in wanted)) extra.push(`${name}: ${has}`);
    else if ((LEVEL[has] || 0) > LEVEL[wanted[name]]) extra.push(`${name}: ${has}, needs only ${wanted[name]}`);
  }
  return { missing, extra };
}

async function checkApps(env, expected, readerSlug) {
  const installations = await env.client.paginate('GET /orgs/{org}/installations', { org: env.org, per_page: 100 });
  const slugs = appSlugs(readerSlug);
  return ['reader', 'writer'].map((role) => {
    const check = `${role} App`;
    const slug = slugs[role];
    if (!slug) {
      return result(env.scope, check, 'unknown', `Can't tell the ${role} App's name: the reader App '${readerSlug}' does not follow <owner>-platform-reader.`);
    }
    const installation = installations.find((item) => item.app_slug === slug);
    if (!installation) return result(env.scope, check, 'fail', `${slug} is not installed on ${env.org}. Install it with All repositories (docs/setup.md, step 4).`);
    if (installation.suspended_at) return result(env.scope, check, 'fail', `${slug} is suspended on ${env.org}. Unsuspend it under Settings > GitHub Apps.`);
    if (installation.repository_selection !== 'all') {
      return result(env.scope, check, 'fail', `${slug} can reach selected repositories only. Give it All repositories, or new repositories are out of its reach.`);
    }
    const { missing, extra } = comparePermissions(installation.permissions || {}, expected.apps[role].permissions);
    if (missing.length > 0) {
      return result(env.scope, check, 'fail', `${slug} is missing ${missing.join(', ')}. Update the App's permissions, then accept the update in this org: Settings > GitHub Apps > ${slug}.`);
    }
    if (extra.length > 0) return result(env.scope, check, 'warn', `${slug} holds more than it needs: ${extra.join(', ')}.`);
    return result(env.scope, check, 'pass', `${slug}: installed on all repositories, with exactly the permissions it needs`);
  });
}

async function checkClassification(env, expected, platformRepository) {
  const property = expected.classification.property;
  const repositories = await env.client.paginate('GET /orgs/{org}/repos', { org: env.org, type: 'all', per_page: 100 });
  const values = await env.client.paginate('GET /orgs/{org}/properties/values', { org: env.org, per_page: 100 });
  const exclude = new Set(expected.classification.exclude);
  if (platformRepository.owner.toLowerCase() === env.org.toLowerCase()) exclude.add(platformRepository.repo);

  const tierOf = new Map(values.map((item) => [
    item.repository_name,
    ((item.properties || []).find((p) => p.property_name === property) || {}).value,
  ]));
  const checked = repositories.filter((repo) => !repo.archived && !exclude.has(repo.name));
  const missing = checked.filter((repo) => !tierOf.get(repo.name)).map((repo) => repo.name).sort();
  const check = `every repository has a ${property}`;
  if (missing.length > 0) {
    return result(env.scope, check, 'warn', `No ${property}: ${missing.join(', ')}. Add them to platform.auto.tfvars, so they get their tier's branch rules.`);
  }
  return result(env.scope, check, 'pass', `${checked.length} repositories classified`);
}

// --- The platform repository --------------------------------------------------

async function checkEnvironments(ctx, expected) {
  const environments = await ctx.client.paginate('GET /repos/{owner}/{repo}/environments', { ...ctx.repo, per_page: 100 });
  const results = [];
  for (const want of expected.platformRepository.environments) {
    const check = `environment ${want.name}`;
    const env = environments.find((item) => item.name === want.name);
    if (!env) {
      results.push(result(ctx.scope, check, 'fail', 'Missing. Run scripts/Initialize-ControlRepo.ps1 with -Apply.'));
      continue;
    }
    const problems = [];
    const notes = [];
    const policy = env.deployment_branch_policy;
    if (!policy || !policy.custom_branch_policies) {
      problems.push(`deploys from ${policy && policy.protected_branches ? 'any protected branch' : 'any branch'}, not only ${want.branches.join(', ')}`);
    } else {
      const policies = await ctx.client.paginate('GET /repos/{owner}/{repo}/environments/{environment_name}/deployment-branch-policies', {
        ...ctx.repo, environment_name: want.name, per_page: 100,
      });
      const names = policies.map((item) => item.name).sort();
      if (names.join(',') !== [...want.branches].sort().join(',')) {
        problems.push(`deploys from ${names.join(', ') || 'no branch'}, expected ${want.branches.join(', ')}`);
      }
    }
    const reviewers = (env.protection_rules || []).filter((rule) => rule.type === 'required_reviewers')
      .flatMap((rule) => rule.reviewers || []);
    if (want.reviewers && reviewers.length === 0) problems.push('nobody has to approve a deployment');
    if (!want.reviewers && reviewers.length > 0) notes.push('has required reviewers, which this environment does not expect');
    if (want.allowAdminBypass === false && env.can_admins_bypass !== false) notes.push('admins can bypass its protection rules');

    if (problems.length > 0) {
      results.push(result(ctx.scope, check, 'fail', `${problems.join('; ')}. Re-run scripts/Initialize-ControlRepo.ps1 with -Apply.`));
    } else if (notes.length > 0) {
      results.push(result(ctx.scope, check, 'warn', notes.join('; ')));
    } else {
      results.push(result(ctx.scope, check, 'pass', `deploys from ${want.branches.join(', ')} only${want.reviewers ? ', after an approval' : ''}`));
    }
  }
  return results;
}

async function checkMainBranch(ctx, expected) {
  const want = expected.platformRepository.mainBranch;
  const rules = await ctx.client.paginate('GET /repos/{owner}/{repo}/rules/branches/{branch}', { ...ctx.repo, branch: want.branch, per_page: 100 });
  const types = new Set(rules.map((rule) => rule.type));
  const problems = want.rules.filter((type) => !types.has(type)).map((type) => `no ${type} rule`);
  const codeOwner = rules.some((rule) => rule.type === 'pull_request' && rule.parameters && rule.parameters.require_code_owner_review);
  if (want.codeOwnerReview && !codeOwner) problems.push('no code owner review');
  const checks = new Set(rules.filter((rule) => rule.type === 'required_status_checks')
    .flatMap((rule) => (rule.parameters && rule.parameters.required_status_checks) || [])
    .map((item) => item.context));
  const missingChecks = want.checks.filter((name) => !checks.has(name));
  if (missingChecks.length > 0) problems.push(`required checks missing: ${missingChecks.join(', ')}`);
  const check = `rules on ${want.branch}`;
  if (problems.length > 0) {
    return result(ctx.scope, check, 'fail', `${problems.join('; ')}. Re-run scripts/Initialize-ControlRepo.ps1 with -Apply.`);
  }
  return result(ctx.scope, check, 'pass', `pull requests only, code owner review, checks: ${want.checks.join(', ')}`);
}

async function checkCodeowners(ctx) {
  let data;
  try {
    ({ data } = await ctx.client.request('GET /repos/{owner}/{repo}/codeowners/errors', ctx.repo));
  } catch (error) {
    if (error && error.status === 404) return result(ctx.scope, 'CODEOWNERS', 'fail', 'No CODEOWNERS file: nobody is asked to review platform changes.');
    throw error;
  }
  const errors = data.errors || [];
  if (errors.length > 0) {
    const list = errors.map((item) => `line ${item.line}: ${item.message || item.kind}`).join('; ');
    return result(ctx.scope, 'CODEOWNERS', 'fail', `${list}. A team that doesn't exist or can't write is silently skipped.`);
  }
  return result(ctx.scope, 'CODEOWNERS', 'pass', 'no errors');
}

async function checkWorkflowRuns(ctx, expected, now) {
  const results = [];
  for (const workflow of expected.platformRepository.workflows) {
    const check = `last ${workflow.file.replace(/\.ya?ml$/, '')} run`;
    const { data } = await ctx.client.request('GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs', {
      ...ctx.repo, workflow_id: workflow.file, branch: workflow.branch, per_page: 20,
    });
    const runs = data.workflow_runs || [];
    const finished = runs.find((run) => run.status === 'completed' && !['cancelled', 'skipped'].includes(run.conclusion));
    const waiting = runs.filter((run) => run.status === 'waiting');
    if (workflow.waitingHours && waiting.length > 0) {
      const oldest = waiting[waiting.length - 1];
      const hours = Math.floor((now - new Date(oldest.created_at)) / 3600000);
      if (hours >= workflow.waitingHours) {
        results.push(result(ctx.scope, `${check}: approval`, 'warn', `Waiting for approval for ${hours} hours: ${oldest.html_url}. Approve it or cancel it, so the next change is not queued behind it.`));
      }
    }
    if (!finished) {
      results.push(result(ctx.scope, check, 'warn', `No finished run on ${workflow.branch} yet.`));
    } else if (finished.conclusion !== 'success') {
      results.push(result(ctx.scope, check, 'fail', `${finished.conclusion} on ${finished.created_at.slice(0, 10)}: ${finished.html_url}`));
    } else {
      results.push(result(ctx.scope, check, 'pass', `succeeded on ${finished.created_at.slice(0, 10)}`));
    }
  }
  return results;
}

async function checkOpenIssues(ctx, expected) {
  const results = [];
  for (const label of expected.platformRepository.openIssueLabels) {
    const issues = (await ctx.client.paginate('GET /repos/{owner}/{repo}/issues', { ...ctx.repo, labels: label, state: 'open', per_page: 100 }))
      .filter((issue) => !issue.pull_request);
    const check = `open ${label} issues`;
    if (issues.length > 0) {
      results.push(result(ctx.scope, check, 'warn', issues.map((issue) => `#${issue.number} ${issue.title}`).join('; ')));
    } else {
      results.push(result(ctx.scope, check, 'pass', 'none'));
    }
  }
  return results;
}

// --- Running and reporting ----------------------------------------------------

async function runChecks({ environments, platform, expected, readerSlug, now }) {
  const results = [];
  for (const env of environments) {
    results.push(...await guarded(env.scope, 'organization settings', () => checkOrganizationSettings(env, expected)));
    for (const setting of expected.organization.actions) {
      results.push(...await guarded(env.scope, setting.field, () => checkActionsSetting(env, setting)));
    }
    results.push(...await guarded(env.scope, 'GitHub Apps', () => checkApps(env, expected, readerSlug)));
    results.push(...await guarded(env.scope, `every repository has a ${expected.classification.property}`, () => checkClassification(env, expected, platform.repo)));
  }
  results.push(...await guarded(platform.scope, 'environments', () => checkEnvironments(platform, expected)));
  results.push(...await guarded(platform.scope, 'rules on main', () => checkMainBranch(platform, expected)));
  results.push(...await guarded(platform.scope, 'CODEOWNERS', () => checkCodeowners(platform)));
  results.push(...await guarded(platform.scope, 'workflow runs', () => checkWorkflowRuns(platform, expected, now)));
  results.push(...await guarded(platform.scope, 'open issues', () => checkOpenIssues(platform, expected)));
  return results;
}

function counts(results) {
  const total = Object.fromEntries(STATUS_ORDER.map((status) => [status, 0]));
  for (const item of results) total[item.status] += 1;
  return total;
}

function escapeCell(text) {
  return String(text).replace(/\|/g, '\\|').replace(/\r?\n/g, ' ');
}

function renderReport(results, { runUrl, checkedAt }) {
  const total = counts(results);
  const ordered = [...results].sort((a, b) => STATUS_ORDER.indexOf(a.status) - STATUS_ORDER.indexOf(b.status));
  const attention = ordered.filter((item) => ['fail', 'warn', 'unknown'].includes(item.status));
  const fine = ordered.filter((item) => ['pass', 'skip'].includes(item.status));
  const row = (item) => `| ${STATUS_LABEL[item.status]} | ${escapeCell(item.scope)} | ${escapeCell(item.check)} | ${escapeCell(item.detail)} |`;
  const lines = [
    `### Platform health: ${total.fail} fail, ${total.warn} warn, ${total.unknown} unknown, ${total.pass} pass`,
    '',
    `Checked ${checkedAt} by [this run](${runUrl}). **Fail** turns the run red, **Warn** is worth a look, **Unknown** could not be read (never a pass).`,
    '',
  ];
  if (attention.length > 0) {
    lines.push('| Status | Where | Check | Detail |', '|---|---|---|---|', ...attention.map(row), '');
  } else {
    lines.push('Nothing needs attention.', '');
  }
  lines.push(`<details><summary>${fine.length} passed or not applicable</summary>`, '', '| Status | Where | Check | Detail |', '|---|---|---|---|', ...fine.map(row), '', '</details>');
  return lines.join('\n');
}

// One issue, opened when something needs attention, rewritten every run, and
// closed once everything passes and everything could be read.
async function syncIssue({ client, repo, results, report, runUrl, log }) {
  const total = counts(results);
  const attention = total.fail + total.warn > 0;
  try {
    await client.request('GET /repos/{owner}/{repo}/labels/{name}', { ...repo, name: ISSUE_LABEL });
  } catch (error) {
    if (!error || error.status !== 404) throw error;
    await client.request('POST /repos/{owner}/{repo}/labels', {
      ...repo, name: ISSUE_LABEL, color: 'b60205', description: 'Something on the platform needs attention',
    });
  }
  const open = (await client.paginate('GET /repos/{owner}/{repo}/issues', { ...repo, labels: ISSUE_LABEL, state: 'open', per_page: 100 }))
    .filter((issue) => !issue.pull_request && issue.title === ISSUE_TITLE);
  const existing = open[0];
  const body = `${report}\n\nThis issue is rewritten by every [platform-health](${runUrl}) run and closes itself once everything passes.`;

  if (attention) {
    if (existing) {
      await client.request('PATCH /repos/{owner}/{repo}/issues/{issue_number}', { ...repo, issue_number: existing.number, body });
      log(`Issue #${existing.number} updated.`);
      return { action: 'updated', number: existing.number };
    }
    const { data } = await client.request('POST /repos/{owner}/{repo}/issues', { ...repo, title: ISSUE_TITLE, body, labels: [ISSUE_LABEL] });
    log(`Issue #${data.number} opened.`);
    return { action: 'opened', number: data.number };
  }
  if (!existing) return { action: 'none' };
  if (total.unknown > 0) {
    await client.request('PATCH /repos/{owner}/{repo}/issues/{issue_number}', { ...repo, issue_number: existing.number, body });
    log(`Issue #${existing.number} kept open: some checks could not be read.`);
    return { action: 'kept', number: existing.number };
  }
  await client.request('POST /repos/{owner}/{repo}/issues/{issue_number}/comments', {
    ...repo, issue_number: existing.number, body: `Resolved: everything passes ([run](${runUrl})).`,
  });
  await client.request('PATCH /repos/{owner}/{repo}/issues/{issue_number}', {
    ...repo, issue_number: existing.number, state: 'closed', state_reason: 'completed',
  });
  log(`Issue #${existing.number} closed.`);
  return { action: 'closed', number: existing.number };
}

// Entry point for actions/github-script.
async function main({ github, context, core, getOctokit }) {
  const workspace = process.env.GITHUB_WORKSPACE || process.cwd();
  const expected = JSON.parse(fs.readFileSync(path.join(workspace, 'scripts', 'platform-health.json'), 'utf8'));
  const environments = ['sandbox', 'prod'].map((name) => {
    const org = process.env[`${name.toUpperCase()}_ORG`];
    const token = process.env[`${name.toUpperCase()}_TOKEN`];
    if (!org || !token) throw new Error(`${name.toUpperCase()}_ORG and ${name.toUpperCase()}_TOKEN must be set.`);
    return { name, org, scope: `${name} (${org})`, client: getOctokit(token) };
  });
  const platform = { scope: `${context.repo.owner}/${context.repo.repo}`, repo: context.repo, client: github };
  const runUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
  const now = new Date();

  const results = await runChecks({ environments, platform, expected, readerSlug: process.env.READER_SLUG, now });
  const report = renderReport(results, { runUrl, checkedAt: now.toISOString().replace(/\.\d+Z$/, 'Z') });
  await core.summary.addRaw(report).write();
  await syncIssue({ client: github, repo: context.repo, results, report, runUrl, log: (text) => core.info(text) });

  const total = counts(results);
  if (total.fail > 0) core.setFailed(`${total.fail} check(s) failed. See the run summary or the ${ISSUE_TITLE} issue.`);
  else if (total.warn > 0) core.warning(`${total.warn} check(s) worth a look. See the ${ISSUE_TITLE} issue.`);
  return total;
}

module.exports = {
  main, runChecks, renderReport, syncIssue, counts, comparePermissions, appSlugs,
};
