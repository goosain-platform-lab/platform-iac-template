# Setup

One-time setup, about 45 minutes. Commands are Windows PowerShell, run from the
repository folder unless a step says otherwise.

**You need:** Terraform (this repo pins 1.16.5 in `.terraform-version`), the GitHub
CLI signed in as the account that owns both orgs (check with `gh auth status`), and
a free HCP Terraform account.

**Placeholders:** `<your-org>` is your prod GitHub org (the one in
`environments/prod.tfvars`), `<your-hcp-org>` your HCP Terraform organization,
`<owner>` the prefix for your GitHub App names, and `<your-github-user>` the
account that approves prod.

## 1. Put the code in the control repository

The control repository must be **public**. On GitHub Free, Environments only work
on public repositories, and the Environments are what hold the writer key and the
prod approval gate. The repository contains no secrets.

```powershell
$org = '<your-org>'

# If you created it private earlier, make it public:
gh repo edit "$org/platform-iac-template" --visibility public --accept-visibility-change-consequences

# Clone it (skip if you already have it), then copy the template files in.
gh repo clone "$org/platform-iac-template"
cd platform-iac-template

# Record provider checksums for Windows, Linux (CI) and Mac, then push.
terraform providers lock -platform=windows_amd64 -platform=linux_amd64 -platform=darwin_arm64
git add -A
git commit -m "Platform template: initial import [skip ci]"
git push origin main
```

`[skip ci]` stops the apply workflow running before its secrets exist. If the
template was already pushed without `.terraform.lock.hcl`, run the
`terraform providers lock` line on a branch and open a pull request with the file
instead; the plan jobs stop with a clear message until it exists.

Optional: mark the repository as a template with
`gh api -X PATCH "repos/$org/platform-iac-template" -F is_template=true`.

## 2. Create the sandbox org

Open <https://github.com/account/organizations/new?plan=free> and create
`<your-org>-sandbox` on the Free plan (the name in `environments/sandbox.tfvars`).
It mirrors prod; every change lands here first.

## 3. HCP Terraform

1. Sign in at <https://app.terraform.io> and create an organization. Any unique
   name works; it is `<your-hcp-org>` below.
2. **Settings > API tokens > Team tokens > Create a team token.** Team: `owners`.
   Expiry: 90 days. Copy the token; it is shown once.

The bootstrap script creates the two workspaces. Don't create them by hand.

## 4. Two GitHub Apps: reader and writer

Create both under **`<your-org>` > Settings > Developer settings > GitHub Apps >
New GitHub App**.

| Setting | Reader | Writer |
|---|---|---|
| Name (unique across GitHub) | `<owner>-platform-reader` | `<owner>-platform-writer` |
| Homepage URL | the repository URL | the repository URL |
| Webhook > Active | unticked | unticked |
| Repository > Administration | Read-only | Read and write |
| Repository > Metadata | Read-only | Read-only |
| Organization > Administration | Read-only | Read and write |
| Organization > Members | Read-only | Read and write |
| Where can it be installed? | Any account | Any account |

"Any account" is needed to install the App on the sandbox org as well. It only
means other accounts *could* install it on their own orgs; it gives nobody access
to yours.

For each App:

1. Copy the **Client ID** from its General page.
2. **Generate a private key.** Move the downloaded `.pem` to `$HOME\keys\`, outside
   the repository. (`.gitignore` blocks `*.pem` anyway.)
3. **Install App** on **both** orgs, with **All repositories** (the writer must be
   able to reach repositories it creates).

## 5. Run the bootstrap script

It checks everything first and changes nothing without `-Apply`.

```powershell
$params = @{
    Repository          = '<your-org>/platform-iac-template'
    TfCloudOrganization = '<your-hcp-org>'
    ReaderClientId      = '<reader client ID>'
    WriterClientId      = '<writer client ID>'
    ReaderKeyPath       = "$HOME\keys\<owner>-platform-reader.pem"
    WriterKeyPath       = "$HOME\keys\<owner>-platform-writer.pem"
    Approver            = '<your-github-user>'
}
.\scripts\Initialize-ControlRepo.ps1 @params          # dry run: read the [PLAN] lines
.\scripts\Initialize-ControlRepo.ps1 @params -Apply   # make the changes
```

It prompts for the HCP token and the billing email. If Windows refuses to run the
script, allow local scripts for this session first:
`Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`.

## 6. First pull request

```powershell
git switch -c first-change
# make any small change, e.g. add a topic to demo-api in platform.auto.tfvars
git commit -am "Add a topic to demo-api"
git push -u origin first-change
gh pr create --fill
```

1. Wait for **checks**, **plan (sandbox)** and **plan (prod)**. Each plan posts a
   comment. The first one shows roughly `1 to import, 23 to add, 1 to change`
   (24 to add in prod): the org settings are adopted, everything else is created.
2. Merge. Working alone you can't approve your own PR, so use **Merge without
   waiting for requirements to be met** (org owners may bypass, but only through a PR).
3. **Actions > terraform-apply:** sandbox applies, then prod waits. Click
   **Review deployments > Approve**.

## 7. Confirm it converged

Run **Actions > terraform-drift > Run workflow**. Both jobs should report no drift.
If an attribute shows up again right after an apply, that is a provider quirk:
add it to `ignore_changes` with a comment saying why (see "Provider quirks" in
[controls.md](controls.md)).

## 8. Settings GitHub has no API for

In **both** orgs:

- **Settings > Authentication security > Require two-factor authentication.**
- **Teams > platform-owners > Add a member:** add yourself (and anyone else who
  approves prod). Members should be org Owners.

## 9. Prove drift detection works

1. In the sandbox org, open **demo-api > Settings > General** and tick
   **Allow merge commits**.
2. Run **terraform-drift**. An issue **Drift detected: sandbox** opens, with the plan
   showing the change.
3. Run **terraform-apply** (approve prod when asked; prod has no changes). The
   setting is switched back off.
4. Run **terraform-drift** again. The issue closes itself.

That loop (break it by hand, watch it get caught, put it back from code) is the
demonstration worth being able to walk through in an interview.

## 10. If another Terraform setup managed these orgs before

- **Do not run `terraform destroy` on the old setup.** Destroying a
  `github_organization_settings` resource makes the provider overwrite the org's
  billing email with `email@example.com`, and its repositories would be deleted.
- If the old code is in a GitHub repository, disable its workflows or archive the
  repository, or its applies and drift checks keep running against the same org.
- Delete repositories you no longer want in the GitHub UI, then delete the old
  setup's local `terraform.tfstate*` files.

## Troubleshooting

| Message | Meaning and fix |
|---|---|
| `Failed to create token for "<org>"` / Not Found | The App isn't installed on that org. Install it (step 4.3). |
| `Resource not accessible by integration` (403) | The App lacks a permission. Compare with the table in step 4. |
| `Terraform failed to find workspace` | Bootstrap step 1 wasn't applied, or `TF_CLOUD_ORGANIZATION` is wrong. |
| `Error acquiring the state lock` | Another run holds the lock. Wait, or unlock it in HCP (workspace > Settings > Locking). |
| `.terraform.lock.hcl is missing` | Run the `terraform providers lock` command from step 1 and commit the file. |
| The same change appears after every apply | A provider quirk: add the attribute to `ignore_changes`, with the reason. |
| HCP token expiring (emails at 30 and 7 days) | Create a new team token and re-run the bootstrap script with `-Apply`. |
| Drift job stopped running | GitHub pauses scheduled workflows in public repos after 60 days without activity. Re-enable it under Actions. |
