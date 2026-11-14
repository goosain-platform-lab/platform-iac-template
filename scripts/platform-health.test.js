'use strict';
// Unit tests for scripts/platform-health.js, against fake GitHub clients.
// Run: node --test scripts/platform-health.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const fs = require('fs');
const health = require('./platform-health.js');

const expected = JSON.parse(fs.readFileSync(path.join(__dirname, 'platform-health.json'), 'utf8'));
const NOW = new Date('2026-11-14T06:00:00Z');

function httpError(status) {
  const error = new Error(`HTTP ${status}`);
  error.status = status;
  return error;
}

// request() returns { data }; paginate() returns the list. A route without a
// fake answers 404, like GitHub does for something that isn't there.
function fakeClient(routes) {
  const calls = [];
  async function handle(route, params) {
    calls.push({ route, params });
    if (!(route in routes)) throw httpError(404);
    const out = typeof routes[route] === 'function' ? routes[route](params) : routes[route];
    if (out instanceof Error) throw out;
    return structuredClone(out);
  }
  return {
    calls,
    request: async (route, params) => ({ data: await handle(route, params) }),
    paginate: async (route, params) => handle(route, params),
  };
}

function orgRoutes(org) {
  // The platform repository lives in the prod org only.
  const repositories = [
    { name: 'demo-api', archived: false },
    { name: 'demo-web', archived: false },
    { name: '.github', archived: false },
    { name: 'old-thing', archived: true },
  ];
  if (org === 'acme-lab') repositories.push({ name: 'platform-iac-template', archived: false });
  return {
    'GET /orgs/{org}': {
      login: org,
      two_factor_requirement_enabled: true,
      members_can_delete_repositories: false,
      members_can_change_repo_visibility: false,
      deploy_keys_enabled_for_repositories: false,
    },
    'GET /orgs/{org}/actions/permissions/fork-pr-contributor-approval': { approval_policy: 'all_external_contributors' },
    'GET /orgs/{org}/installations': [
      { app_slug: 'acme-platform-reader', repository_selection: 'all', suspended_at: null, permissions: { ...expected.apps.reader.permissions } },
      { app_slug: 'acme-platform-writer', repository_selection: 'all', suspended_at: null, permissions: { ...expected.apps.writer.permissions } },
      { app_slug: 'some-other-app', repository_selection: 'selected', permissions: { contents: 'write' } },
    ],
    'GET /orgs/{org}/repos': repositories,
    'GET /orgs/{org}/properties/values': [
      { repository_name: 'demo-api', properties: [{ property_name: 'criticality', value: 'tier-3' }] },
      { repository_name: 'demo-web', properties: [{ property_name: 'criticality', value: 'tier-3' }] },
    ],
  };
}

function platformRoutes() {
  return {
    'GET /repos/{owner}/{repo}/environments': [
      { name: 'sandbox', deployment_branch_policy: { protected_branches: false, custom_branch_policies: true }, protection_rules: [], can_admins_bypass: true },
      {
        name: 'prod',
        deployment_branch_policy: { protected_branches: false, custom_branch_policies: true },
        protection_rules: [{ type: 'required_reviewers', reviewers: [{ type: 'User', reviewer: { login: 'owner' } }] }],
        can_admins_bypass: true,
      },
    ],
    'GET /repos/{owner}/{repo}/environments/{environment_name}/deployment-branch-policies': [{ name: 'main', type: 'branch' }],
    'GET /repos/{owner}/{repo}/rules/branches/{branch}': [
      { type: 'deletion' },
      { type: 'non_fast_forward' },
      { type: 'pull_request', parameters: { require_code_owner_review: true } },
      { type: 'required_status_checks', parameters: { required_status_checks: [{ context: 'checks' }, { context: 'plan (sandbox)' }, { context: 'plan (prod)' }] } },
    ],
    'GET /repos/{owner}/{repo}/codeowners/errors': { errors: [] },
    'GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs': {
      workflow_runs: [{ status: 'completed', conclusion: 'success', created_at: '2026-11-13T04:00:00Z', html_url: 'https://example.test/run/1' }],
    },
    'GET /repos/{owner}/{repo}/issues': [],
  };
}

function setup({ sandbox = {}, prod = {}, platform = {} } = {}) {
  const environments = [
    { name: 'sandbox', org: 'acme-lab-sandbox', scope: 'sandbox (acme-lab-sandbox)', client: fakeClient({ ...orgRoutes('acme-lab-sandbox'), ...sandbox }) },
    { name: 'prod', org: 'acme-lab', scope: 'prod (acme-lab)', client: fakeClient({ ...orgRoutes('acme-lab'), ...prod }) },
  ];
  const platformCtx = {
    scope: 'acme-lab/platform-iac-template',
    repo: { owner: 'acme-lab', repo: 'platform-iac-template' },
    client: fakeClient({ ...platformRoutes(), ...platform }),
  };
  return { environments, platform: platformCtx, expected, readerSlug: 'acme-platform-reader', now: NOW };
}

const find = (results, scope, check) => results.find((item) => item.scope.startsWith(scope) && item.check === check);
const statuses = (results) => results.map((item) => item.status);

test('a healthy platform passes every check', async () => {
  const results = await health.runChecks(setup());
  assert.deepEqual([...new Set(statuses(results))], ['pass'], JSON.stringify(results.filter((r) => r.status !== 'pass'), null, 1));
  assert.ok(results.length >= 20);
});

test('two-factor authentication switched off fails', async () => {
  const results = await health.runChecks(setup({ prod: { 'GET /orgs/{org}': { two_factor_requirement_enabled: false, members_can_delete_repositories: false, members_can_change_repo_visibility: false } } }));
  assert.equal(find(results, 'prod', 'two_factor_requirement_enabled').status, 'fail');
  assert.equal(find(results, 'prod', 'deploy_keys_enabled_for_repositories').status, 'skip', 'a field the plan does not return is not applicable');
  assert.equal(find(results, 'sandbox', 'two_factor_requirement_enabled').status, 'pass');
});

test('a member privilege the API cannot set is a warning, with the fix', async () => {
  const results = await health.runChecks(setup({ sandbox: { 'GET /orgs/{org}': { two_factor_requirement_enabled: true, members_can_delete_repositories: true, members_can_change_repo_visibility: false } } }));
  const item = find(results, 'sandbox', 'members_can_delete_repositories');
  assert.equal(item.status, 'warn');
  assert.match(item.detail, /Member privileges/);
});

test('a missed App permission update fails, and an extra permission warns', async () => {
  const installations = orgRoutes('acme-lab')['GET /orgs/{org}/installations'];
  delete installations[1].permissions.repository_custom_properties;
  installations[0].permissions.contents = 'write';
  const results = await health.runChecks(setup({ prod: { 'GET /orgs/{org}/installations': installations } }));
  const writer = find(results, 'prod', 'writer App');
  assert.equal(writer.status, 'fail');
  assert.match(writer.detail, /repository_custom_properties \(needs write, has none\)/);
  assert.match(writer.detail, /accept the update/);
  assert.equal(find(results, 'prod', 'reader App').status, 'warn');
});

test('an App missing from an org, or limited to some repositories, fails', async () => {
  const installations = orgRoutes('acme-lab-sandbox')['GET /orgs/{org}/installations'];
  installations[0].repository_selection = 'selected';
  installations.splice(1, 1);
  const results = await health.runChecks(setup({ sandbox: { 'GET /orgs/{org}/installations': installations } }));
  assert.match(find(results, 'sandbox', 'reader App').detail, /selected repositories only/);
  assert.match(find(results, 'sandbox', 'writer App').detail, /not installed/);
});

test("the writer App's name comes from the naming convention, or is Unknown", async () => {
  assert.deepEqual(health.appSlugs('acme-platform-reader'), { reader: 'acme-platform-reader', writer: 'acme-platform-writer' });
  const results = await health.runChecks({ ...setup(), readerSlug: 'my-reader-app' });
  assert.equal(find(results, 'prod', 'writer App').status, 'unknown');
});

test('a repository without a tier is listed; archived, .github and the platform repository are not', async () => {
  const results = await health.runChecks(setup({
    prod: {
      'GET /orgs/{org}/repos': [
        { name: 'demo-api', archived: false }, { name: 'hand-made', archived: false },
        { name: '.github', archived: false }, { name: 'platform-iac-template', archived: false }, { name: 'old', archived: true },
      ],
    },
  }));
  const item = find(results, 'prod', 'every repository has a criticality');
  assert.equal(item.status, 'warn');
  assert.match(item.detail, /^No criticality: hand-made\./);
});

test('the platform repository is excluded only in the org that holds it', async () => {
  const results = await health.runChecks(setup({
    sandbox: { 'GET /orgs/{org}/repos': [{ name: 'platform-iac-template', archived: false }] },
  }));
  assert.equal(find(results, 'sandbox', 'every repository has a criticality').status, 'warn');
});

test('a check the token cannot read is Unknown, never a pass', async () => {
  const results = await health.runChecks(setup({ prod: { 'GET /orgs/{org}/properties/values': httpError(403) } }));
  const item = find(results, 'prod', 'every repository has a criticality');
  assert.equal(item.status, 'unknown');
  assert.match(item.detail, /HTTP 403/);
});

test('an unprotected prod environment fails', async () => {
  const environments = platformRoutes()['GET /repos/{owner}/{repo}/environments'];
  environments[1].protection_rules = [];
  environments[1].deployment_branch_policy = null;
  const results = await health.runChecks(setup({ platform: { 'GET /repos/{owner}/{repo}/environments': environments } }));
  const item = find(results, 'acme-lab/platform', 'environment prod');
  assert.equal(item.status, 'fail');
  assert.match(item.detail, /any branch/);
  assert.match(item.detail, /nobody has to approve/);
});

test('a missing environment, or one deploying from another branch, fails', async () => {
  const results = await health.runChecks(setup({
    platform: {
      'GET /repos/{owner}/{repo}/environments': [platformRoutes()['GET /repos/{owner}/{repo}/environments'][1]],
      'GET /repos/{owner}/{repo}/environments/{environment_name}/deployment-branch-policies': [{ name: 'main' }, { name: 'release/*' }],
    },
  }));
  assert.match(find(results, 'acme-lab/platform', 'environment sandbox').detail, /^Missing/);
  assert.match(find(results, 'acme-lab/platform', 'environment prod').detail, /release\/\*/);
});

test('main without a required plan check fails', async () => {
  const rules = platformRoutes()['GET /repos/{owner}/{repo}/rules/branches/{branch}'];
  rules[3].parameters.required_status_checks.pop();
  rules[2].parameters.require_code_owner_review = false;
  const results = await health.runChecks(setup({ platform: { 'GET /repos/{owner}/{repo}/rules/branches/{branch}': rules } }));
  const item = find(results, 'acme-lab/platform', 'rules on main');
  assert.equal(item.status, 'fail');
  assert.match(item.detail, /no code owner review/);
  assert.match(item.detail, /plan \(prod\)/);
});

test('CODEOWNERS errors and a missing CODEOWNERS file fail', async () => {
  let results = await health.runChecks(setup({ platform: { 'GET /repos/{owner}/{repo}/codeowners/errors': { errors: [{ line: 1, message: 'Unknown owner' }] } } }));
  assert.match(find(results, 'acme-lab/platform', 'CODEOWNERS').detail, /line 1: Unknown owner/);
  results = await health.runChecks(setup({ platform: { 'GET /repos/{owner}/{repo}/codeowners/errors': httpError(404) } }));
  assert.match(find(results, 'acme-lab/platform', 'CODEOWNERS').detail, /No CODEOWNERS file/);
});

test('a failed apply fails, and an approval waiting a day warns', async () => {
  const runs = {
    workflow_runs: [
      { status: 'waiting', created_at: '2026-11-13T05:00:00Z', html_url: 'https://example.test/run/9' },
      { status: 'completed', conclusion: 'cancelled', created_at: '2026-11-11T05:00:00Z', html_url: 'https://example.test/run/8' },
      { status: 'completed', conclusion: 'failure', created_at: '2026-11-10T05:00:00Z', html_url: 'https://example.test/run/7' },
    ],
  };
  const results = await health.runChecks(setup({ platform: { 'GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs': runs } }));
  const apply = find(results, 'acme-lab/platform', 'last terraform-apply run');
  assert.equal(apply.status, 'fail');
  assert.match(apply.detail, /run\/7/, 'a cancelled run is skipped over');
  assert.match(find(results, 'acme-lab/platform', 'last terraform-apply run: approval').detail, /25 hours/);
  assert.equal(find(results, 'acme-lab/platform', 'last terraform-drift run').status, 'fail');
});

test('an open drift issue is worth a look', async () => {
  const results = await health.runChecks(setup({ platform: { 'GET /repos/{owner}/{repo}/issues': [{ number: 4, title: 'Drift detected: prod' }, { number: 5, title: 'A PR', pull_request: {} }] } }));
  const item = find(results, 'acme-lab/platform', 'open drift issues');
  assert.equal(item.status, 'warn');
  assert.equal(item.detail, '#4 Drift detected: prod');
});

test('the report lists what needs attention first, escapes table cells, and counts every status', () => {
  const report = health.renderReport([
    { scope: 's', check: 'a', status: 'pass', detail: 'ok' },
    { scope: 's', check: 'b', status: 'fail', detail: 'x | y' },
    { scope: 's', check: 'c', status: 'unknown', detail: 'HTTP 403' },
  ], { runUrl: 'https://example.test/run/1', checkedAt: '2026-11-14T06:00:00Z' });
  assert.match(report, /^### Platform health: 1 fail, 0 warn, 1 unknown, 1 pass/);
  assert.ok(report.indexOf('| FAIL |') < report.indexOf('| UNKNOWN |'));
  assert.ok(report.includes('x \\| y'));
  assert.ok(report.includes('<details><summary>1 passed or not applicable</summary>'));
});

function issueClient({ open = [], labelExists = true } = {}) {
  return fakeClient({
    'GET /repos/{owner}/{repo}/labels/{name}': labelExists ? { name: 'platform-health' } : httpError(404),
    'POST /repos/{owner}/{repo}/labels': {},
    'GET /repos/{owner}/{repo}/issues': open,
    'POST /repos/{owner}/{repo}/issues': { number: 12 },
    'PATCH /repos/{owner}/{repo}/issues/{issue_number}': {},
    'POST /repos/{owner}/{repo}/issues/{issue_number}/comments': {},
  });
}
const repo = { owner: 'acme-lab', repo: 'platform-iac-template' };
const quiet = () => {};

test('the issue opens when something needs attention, creating its label once', async () => {
  const client = issueClient({ labelExists: false });
  const out = await health.syncIssue({ client, repo, results: [{ status: 'warn' }], report: 'r', runUrl: 'u', log: quiet });
  assert.deepEqual(out, { action: 'opened', number: 12 });
  assert.ok(client.calls.some((call) => call.route === 'POST /repos/{owner}/{repo}/labels'));
});

test('an open issue is rewritten, not duplicated', async () => {
  const client = issueClient({ open: [{ number: 3, title: 'Platform health' }] });
  const out = await health.syncIssue({ client, repo, results: [{ status: 'fail' }], report: 'r', runUrl: 'u', log: quiet });
  assert.deepEqual(out, { action: 'updated', number: 3 });
  assert.ok(!client.calls.some((call) => call.route === 'POST /repos/{owner}/{repo}/issues'));
});

test('the issue closes itself only when everything passes and could be read', async () => {
  let client = issueClient({ open: [{ number: 3, title: 'Platform health' }] });
  let out = await health.syncIssue({ client, repo, results: [{ status: 'pass' }, { status: 'unknown' }], report: 'r', runUrl: 'u', log: quiet });
  assert.deepEqual(out, { action: 'kept', number: 3 });

  client = issueClient({ open: [{ number: 3, title: 'Platform health' }] });
  out = await health.syncIssue({ client, repo, results: [{ status: 'pass' }, { status: 'skip' }], report: 'r', runUrl: 'u', log: quiet });
  assert.deepEqual(out, { action: 'closed', number: 3 });
  const close = client.calls.find((call) => call.route === 'PATCH /repos/{owner}/{repo}/issues/{issue_number}');
  assert.equal(close.params.state, 'closed');
});

test('no issue is opened just because something could not be read', async () => {
  const client = issueClient();
  const out = await health.syncIssue({ client, repo, results: [{ status: 'unknown' }, { status: 'pass' }], report: 'r', runUrl: 'u', log: quiet });
  assert.deepEqual(out, { action: 'none' });
});

test('main() fails the run on a failure, and reads its orgs and tokens from the environment', async () => {
  const env = setup({ prod: { 'GET /orgs/{org}': { two_factor_requirement_enabled: false } } });
  const clients = { 'sandbox-token': env.environments[0].client, 'prod-token': env.environments[1].client };
  Object.assign(process.env, {
    SANDBOX_ORG: 'acme-lab-sandbox', SANDBOX_TOKEN: 'sandbox-token', PROD_ORG: 'acme-lab', PROD_TOKEN: 'prod-token',
    READER_SLUG: 'acme-platform-reader', GITHUB_WORKSPACE: path.join(__dirname, '..'),
  });
  const failures = [];
  let summary = '';
  // The workflow's own token reads the platform repository and writes the issue.
  const platformRoutesClient = fakeClient({ ...platformRoutes(), ...issueClientRoutes() });
  const core = {
    summary: { addRaw(text) { summary = text; return this; }, async write() {} },
    info: quiet, warning: quiet, setFailed: (message) => failures.push(message),
  };
  const total = await health.main({
    github: platformRoutesClient,
    context: { repo, serverUrl: 'https://github.com', runId: 1 },
    core,
    getOctokit: (token) => clients[token],
  });
  assert.ok(total.fail >= 1);
  assert.equal(failures.length, 1);
  assert.match(summary, /two_factor_requirement_enabled/);
});

function issueClientRoutes() {
  return {
    'GET /repos/{owner}/{repo}/labels/{name}': { name: 'platform-health' },
    'POST /repos/{owner}/{repo}/issues': { number: 12 },
    'PATCH /repos/{owner}/{repo}/issues/{issue_number}': {},
  };
}
