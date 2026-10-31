#Requires -Version 5.1
<#
.SYNOPSIS
    One-time setup of the control repository and its HCP Terraform workspaces.

.DESCRIPTION
    READ-ONLY UNLESS YOU ADD -Apply. Without -Apply the script checks every
    prerequisite and prints a [PLAN] line for each change it would make. Run it
    that way first, read the output, then run the same command with -Apply.

    With -Apply it creates or updates the following. It never deletes anything.
      1. HCP Terraform workspaces github-platform-<environment>, execution mode Local.
      2. Repository variables: TF_CLOUD_ORGANIZATION, GH_APP_READER_CLIENT_ID,
         GH_APP_WRITER_CLIENT_ID.
      3. Repository secrets: TF_API_TOKEN, GH_APP_READER_PRIVATE_KEY,
         ORG_BILLING_EMAIL. The same three, plus TF_CLOUD_ORGANIZATION and
         GH_APP_READER_CLIENT_ID, are stored as Dependabot secrets so Dependabot
         pull requests can be planned too.
      4. Environments sandbox and prod: deployable from main only; prod waits for
         -Approver. The writer App key GH_APP_WRITER_PRIVATE_KEY is stored on each
         Environment, so only jobs running from main can read it.
      5. This repository's own settings: squash-only merges, merged branches
         deleted, secret scanning, push protection, Dependabot alerts and updates.
      6. Ruleset default-branch-protection on main: changes arrive by pull request
         with code-owner review, and the checks and plan jobs must pass.

    The HCP Terraform token and the billing email are prompted for (or read from
    $env:TF_API_TOKEN and $env:ORG_BILLING_EMAIL), never passed as parameters,
    so they stay out of your shell history.

    Where to run: Windows PowerShell 5.1 or PowerShell 7, from the repository
    root, with gh signed in as an owner of both orgs.

.EXAMPLE
    .\scripts\Initialize-ControlRepo.ps1 `
        -Repository <your-org>/platform-iac-template `
        -TfCloudOrganization <your-hcp-org> `
        -ReaderClientId Iv23liReaderXXXX -WriterClientId Iv23liWriterXXXX `
        -ReaderKeyPath "$HOME\keys\<owner>-platform-reader.pem" `
        -WriterKeyPath "$HOME\keys\<owner>-platform-writer.pem" `
        -Approver <your-github-user>

    Dry run. Add -Apply to the same command to make the changes.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive console script: the coloured status lines are its output.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$')]
    [string] $Repository,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string] $TfCloudOrganization,

    [Parameter(Mandatory = $true)]
    [string] $ReaderClientId,

    [Parameter(Mandatory = $true)]
    [string] $WriterClientId,

    [Parameter(Mandatory = $true)]
    [string] $ReaderKeyPath,

    [Parameter(Mandatory = $true)]
    [string] $WriterKeyPath,

    [Parameter(Mandatory = $true)]
    [string] $Approver,

    [string[]] $Environments = @('sandbox', 'prod'),

    [string] $ApprovalEnvironment = 'prod',

    [string[]] $RequiredChecks,

    [string] $TfCloudBaseUri = 'https://app.terraform.io',

    [switch] $Apply
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false # exit codes are checked explicitly below
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { $null = $_ }
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
catch { $null = $_ }

$script:ChangeCount = 0
$script:TfApiToken = $null
$owner = $Repository.Split('/')[0]
$workspacePrefix = 'github-platform'
$rulesetName = 'default-branch-protection'
if (-not $PSBoundParameters.ContainsKey('RequiredChecks')) {
    $RequiredChecks = @('checks') + @($Environments | ForEach-Object { "plan ($_)" })
}

# --- Output helpers ---------------------------------------------------------

function Write-Section([string] $Text) {
    Write-Host ''
    Write-Host "== $Text" -ForegroundColor Cyan
}

function Write-Ok([string] $Text) {
    Write-Host "   [OK]   $Text" -ForegroundColor Green
}

function Write-Note([string] $Text) {
    Write-Host "   [NOTE] $Text" -ForegroundColor DarkYellow
}

function Write-Change([string] $Text) {
    $script:ChangeCount++
    if ($Apply) { Write-Host "   [DO]   $Text" -ForegroundColor Yellow }
    else { Write-Host "   [PLAN] $Text" -ForegroundColor Yellow }
}

function Exit-Setup([string] $Text) {
    Write-Host ''
    Write-Host "STOPPED: $Text" -ForegroundColor Red
    Write-Host 'Nothing after this point was changed.' -ForegroundColor Red
    exit 1
}

# --- gh and HCP Terraform helpers -------------------------------------------

function Invoke-Gh {
    param(
        [Parameter(Mandatory = $true)] [string[]] $Arguments,
        [Parameter(Mandatory = $true)] [string] $What,
        [string] $InputText
    )
    if ($PSBoundParameters.ContainsKey('InputText')) {
        $output = $InputText | & gh @Arguments
    }
    else {
        $output = & gh @Arguments
    }
    if ($LASTEXITCODE -ne 0) {
        Exit-Setup "$What failed (gh exit code $LASTEXITCODE). The gh message above says why."
    }
    return (@($output) -join "`n")
}

function Get-GhJson {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $What
    )
    $text = Invoke-Gh -Arguments @('api', $Path) -What $What
    if ([string]::IsNullOrWhiteSpace($text)) { Exit-Setup "$What returned nothing." }
    return (ConvertFrom-Json -InputObject $text)
}

function Invoke-Hcp {
    param(
        [Parameter(Mandatory = $true)] [string] $Method,
        [Parameter(Mandatory = $true)] [string] $Path,
        [object] $Body,
        [switch] $AllowNotFound
    )
    $request = @{
        Uri             = "$TfCloudBaseUri/api/v2/$Path"
        Method          = $Method
        Headers         = @{ Authorization = "Bearer $script:TfApiToken" }
        ContentType     = 'application/vnd.api+json'
        UseBasicParsing = $true
    }
    if ($null -ne $Body) { $request.Body = ConvertTo-Json -InputObject $Body -Depth 10 }
    try {
        $response = Invoke-WebRequest @request
    }
    catch {
        $status = 0
        if ($null -ne $_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        if ($AllowNotFound -and $status -eq 404) { return $null }
        Exit-Setup "HCP Terraform $Method /api/v2/$Path failed (HTTP $status): $($_.Exception.Message)"
    }
    $content = $response.Content
    if ($content -is [byte[]]) { $content = [System.Text.Encoding]::UTF8.GetString($content) }
    if ([string]::IsNullOrWhiteSpace($content)) { return $null }
    return (ConvertFrom-Json -InputObject $content)
}

# --- Prerequisites (read-only) ----------------------------------------------

Write-Host ''
if ($Apply) {
    Write-Host 'Mode: APPLY. Changes will be made.' -ForegroundColor Yellow
}
else {
    Write-Host 'Mode: DRY RUN (read-only). Nothing will be changed. Add -Apply to make the changes.' -ForegroundColor Green
}

Write-Section 'Checking prerequisites (read-only)'

if (-not (Test-Path -Path 'environments' -PathType Container) -or -not (Test-Path -Path '.terraform-version' -PathType Leaf)) {
    Exit-Setup 'Run this from the repository root (the folder that contains environments\ and .terraform-version).'
}
if ($null -eq (Get-Command gh -ErrorAction SilentlyContinue)) {
    Exit-Setup 'The GitHub CLI (gh) is not installed. Install it with: winget install GitHub.cli'
}
if ($Environments -notcontains $ApprovalEnvironment) {
    Exit-Setup "-ApprovalEnvironment '$ApprovalEnvironment' is not one of -Environments ($($Environments -join ', '))."
}
if ($ReaderClientId -eq $WriterClientId) {
    Exit-Setup 'The reader and writer client IDs are the same. They must be two different GitHub Apps.'
}

$me = Get-GhJson -Path 'user' -What 'Reading the signed-in GitHub user'
Write-Ok "gh is signed in as $($me.login)"

$repo = Get-GhJson -Path "repos/$Repository" -What "Reading $Repository"
if (-not $repo.permissions.admin) { Exit-Setup "$($me.login) is not an admin of $Repository." }
Write-Ok "$Repository exists (visibility: $($repo.visibility)) and you are an admin"

$org = Get-GhJson -Path "orgs/$owner" -What "Reading org $owner"
$orgPlan = 'unknown'
if ($null -ne $org.plan) { $orgPlan = $org.plan.name }
if ($orgPlan -eq 'free' -and $repo.visibility -ne 'public') {
    Exit-Setup ("$owner is on GitHub Free, where Environments (the prod approval gate and the protected writer key) only work on public repositories. " +
        "Make this repository public first: gh repo edit $Repository --visibility public --accept-visibility-change-consequences")
}
Write-Ok "Org $owner is on the '$orgPlan' plan"

foreach ($name in $Environments) {
    $file = Join-Path 'environments' "$name.tfvars"
    if (-not (Test-Path -Path $file -PathType Leaf)) {
        Exit-Setup "$file not found. -Environments must match the files in environments\."
    }
    $match = Select-String -Path $file -Pattern '^\s*github_org\s*=\s*"([^"]+)"' | Select-Object -First 1
    if ($null -eq $match) { Exit-Setup "github_org is not set in $file." }
    $envOrg = $match.Matches[0].Groups[1].Value
    $membership = Get-GhJson -Path "orgs/$envOrg/memberships/$($me.login)" -What "Checking your role in $envOrg (environment $name; does that org exist?)"
    if ($membership.role -ne 'admin') {
        Exit-Setup "$($me.login) must be an owner of $envOrg, but the role is '$($membership.role)'."
    }
    Write-Ok "Environment $name manages org $envOrg, where you are an owner"
}

foreach ($keyFile in @($ReaderKeyPath, $WriterKeyPath)) {
    if (-not (Test-Path -Path $keyFile -PathType Leaf)) { Exit-Setup "Key file not found: $keyFile" }
    $firstLine = Get-Content -Path $keyFile -TotalCount 1
    if ($firstLine -notmatch '^-----BEGIN (RSA )?PRIVATE KEY-----$') {
        Exit-Setup "$keyFile does not look like a GitHub App private key (.pem file)."
    }
}
$readerKey = Get-Content -Path $ReaderKeyPath -Raw
$writerKey = Get-Content -Path $WriterKeyPath -Raw
if ($readerKey -eq $writerKey) {
    Exit-Setup 'The reader and writer keys are identical. Each GitHub App has its own key.'
}
Write-Ok 'Reader and writer App keys found, and they differ'

$approverUser = Get-GhJson -Path "users/$Approver" -What "Looking up the approver $Approver"
if ($approverUser.type -ne 'User') { Exit-Setup "$Approver is not a user account." }
Write-Ok "Prod deployments will wait for $($approverUser.login) (user id $($approverUser.id))"

$pinned = (Get-Content -Path '.terraform-version' -Raw).Trim()
if ($null -eq (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Note "terraform is not on PATH. CI uses $pinned."
}
else {
    $versionJson = & terraform version -json
    if ($LASTEXITCODE -eq 0) {
        $localVersion = (ConvertFrom-Json -InputObject (@($versionJson) -join "`n")).terraform_version
        if ($localVersion -eq $pinned) { Write-Ok "Local Terraform $localVersion matches .terraform-version" }
        else { Write-Note "Local Terraform is $localVersion; CI uses $pinned (.terraform-version). Fine for plans; match them when convenient." }
    }
}

Write-Section 'Secrets (typed here, so they stay out of your shell history)'

if (-not [string]::IsNullOrWhiteSpace($env:TF_API_TOKEN)) {
    $script:TfApiToken = $env:TF_API_TOKEN
    Write-Ok 'Using the HCP Terraform token from $env:TF_API_TOKEN'
}
else {
    $secureToken = Read-Host -Prompt '   HCP Terraform team API token' -AsSecureString
    $script:TfApiToken = (New-Object System.Net.NetworkCredential -ArgumentList '', $secureToken).Password
}
if ([string]::IsNullOrWhiteSpace($script:TfApiToken)) { Exit-Setup 'The HCP Terraform token is empty.' }

if (-not [string]::IsNullOrWhiteSpace($env:ORG_BILLING_EMAIL)) {
    $billingEmail = $env:ORG_BILLING_EMAIL.Trim()
    Write-Ok 'Using the billing email from $env:ORG_BILLING_EMAIL'
}
else {
    $billingEmail = (Read-Host -Prompt '   Billing email of the orgs (Terraform reads it, never changes it)').Trim()
}
if ($billingEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$' -or $billingEmail -match '@example\.(com|org|net)$') {
    Exit-Setup 'The billing email is not a usable email address.'
}

$null = Invoke-Hcp -Method GET -Path "organizations/$TfCloudOrganization"
Write-Ok "The token can read HCP Terraform organization $TfCloudOrganization"

# --- Step 1: HCP Terraform workspaces ---------------------------------------

Write-Section 'Step 1/6  HCP Terraform workspaces (Local execution: HCP keeps state, GitHub Actions runs Terraform)'

foreach ($name in $Environments) {
    $workspace = "$workspacePrefix-$name"
    $existing = Invoke-Hcp -Method GET -Path "organizations/$TfCloudOrganization/workspaces/$workspace" -AllowNotFound
    $body = @{
        data = @{
            type       = 'workspaces'
            attributes = [ordered]@{
                name                 = $workspace
                'execution-mode'     = 'local'
                'setting-overwrites' = @{ 'execution-mode' = $true }
                description          = "GitHub platform config, $name environment. State only: plans and applies run in GitHub Actions."
            }
        }
    }
    if ($null -eq $existing) {
        Write-Change "create workspace $workspace (execution mode Local)"
        if ($Apply) { $null = Invoke-Hcp -Method POST -Path "organizations/$TfCloudOrganization/workspaces" -Body $body }
    }
    elseif ($existing.data.attributes.'execution-mode' -ne 'local') {
        Write-Change "switch workspace $workspace from '$($existing.data.attributes.'execution-mode')' to Local execution"
        if ($Apply) { $null = Invoke-Hcp -Method PATCH -Path "organizations/$TfCloudOrganization/workspaces/$workspace" -Body $body }
    }
    else {
        Write-Ok "workspace $workspace exists with Local execution"
    }
}

# --- Step 2: repository variables -------------------------------------------

Write-Section 'Step 2/6  Repository variables (not secret)'

$currentVariables = @{}
$variableList = Get-GhJson -Path "repos/$Repository/actions/variables?per_page=100" -What 'Listing repository variables'
foreach ($variable in @($variableList.variables)) {
    if ($null -ne $variable) { $currentVariables[$variable.name] = $variable.value }
}
$desiredVariables = [ordered]@{
    TF_CLOUD_ORGANIZATION   = $TfCloudOrganization
    GH_APP_READER_CLIENT_ID = $ReaderClientId
    GH_APP_WRITER_CLIENT_ID = $WriterClientId
}
foreach ($name in $desiredVariables.Keys) {
    $value = $desiredVariables[$name]
    if ($currentVariables.ContainsKey($name) -and $currentVariables[$name] -eq $value) {
        Write-Ok "$name = $value"
        continue
    }
    Write-Change "set variable $name = $value"
    if ($Apply) {
        $null = Invoke-Gh -Arguments @('variable', 'set', $name, '--repo', $Repository, '--body', $value) -What "Setting variable $name"
    }
}

# --- Step 3: repository and Dependabot secrets ------------------------------

Write-Section 'Step 3/6  Repository and Dependabot secrets (GitHub never shows secrets back, so they are always re-set)'

$repositorySecrets = [ordered]@{
    TF_API_TOKEN              = $script:TfApiToken
    GH_APP_READER_PRIVATE_KEY = $readerKey
    ORG_BILLING_EMAIL         = $billingEmail
}
foreach ($name in $repositorySecrets.Keys) {
    foreach ($app in @('actions', 'dependabot')) {
        Write-Change "set $app secret $name"
        if ($Apply) {
            $null = Invoke-Gh -Arguments @('secret', 'set', $name, '--repo', $Repository, '--app', $app) -InputText $repositorySecrets[$name] -What "Setting $app secret $name"
        }
    }
}

# Dependabot runs only see Dependabot secrets, so the two non-secret values the
# plan workflow needs are stored there as well (terraform-plan.yml falls back to them).
$dependabotFallbacks = [ordered]@{
    TF_CLOUD_ORGANIZATION   = $TfCloudOrganization
    GH_APP_READER_CLIENT_ID = $ReaderClientId
}
foreach ($name in $dependabotFallbacks.Keys) {
    Write-Change "set dependabot secret $name (fallback for Dependabot pull requests)"
    if ($Apply) {
        $null = Invoke-Gh -Arguments @('secret', 'set', $name, '--repo', $Repository, '--app', 'dependabot') -InputText $dependabotFallbacks[$name] -What "Setting dependabot secret $name"
    }
}

# --- Step 4: Environments ---------------------------------------------------

Write-Section 'Step 4/6  Environments (main branch only, approval on prod, writer key)'

$environmentList = Get-GhJson -Path "repos/$Repository/environments?per_page=100" -What 'Listing environments'
$existingEnvironments = @{}
foreach ($environment in @($environmentList.environments)) {
    if ($null -ne $environment) { $existingEnvironments[$environment.name] = $environment }
}

foreach ($name in $Environments) {
    $settings = [ordered]@{
        wait_timer               = 0
        deployment_branch_policy = [ordered]@{ protected_branches = $false; custom_branch_policies = $true }
    }
    $detail = 'deployable from main only'
    if ($name -eq $ApprovalEnvironment) {
        $settings.reviewers = @(@{ type = 'User'; id = $approverUser.id })
        $settings.prevent_self_review = $false
        $detail += ", waits for $($approverUser.login) to approve"
    }

    $exists = $existingEnvironments.ContainsKey($name)
    $verb = 'create'
    if ($exists) { $verb = 'update' }
    Write-Change "$verb environment $name ($detail)"
    if ($Apply) {
        $null = Invoke-Gh -Arguments @('api', '--method', 'PUT', "repos/$Repository/environments/$name", '--input', '-') -InputText (ConvertTo-Json -InputObject $settings -Depth 10) -What "Configuring environment $name"
    }

    # Branch policies can only be listed once the environment uses custom
    # policies, which it does after the update above (or already did).
    $usesCustomPolicies = $false
    if ($exists -and $null -ne $existingEnvironments[$name].deployment_branch_policy) {
        $usesCustomPolicies = [bool]$existingEnvironments[$name].deployment_branch_policy.custom_branch_policies
    }
    $hasMainPolicy = $false
    if ($Apply -or $usesCustomPolicies) {
        $policies = Get-GhJson -Path "repos/$Repository/environments/$name/deployment-branch-policies" -What "Listing branch policies for $name"
        $hasMainPolicy = @(@($policies.branch_policies) | Where-Object { $null -ne $_ -and $_.name -eq 'main' }).Count -gt 0
    }
    if ($hasMainPolicy) {
        Write-Ok "environment $name accepts deployments from main"
    }
    else {
        Write-Change "allow deployments to $name from branch main"
        if ($Apply) {
            $null = Invoke-Gh -Arguments @('api', '--method', 'POST', "repos/$Repository/environments/$name/deployment-branch-policies", '-f', 'name=main', '-f', 'type=branch') -What "Adding branch policy main to $name"
        }
    }

    Write-Change "set environment secret GH_APP_WRITER_PRIVATE_KEY on $name"
    if ($Apply) {
        $null = Invoke-Gh -Arguments @('secret', 'set', 'GH_APP_WRITER_PRIVATE_KEY', '--repo', $Repository, '--env', $name) -InputText $writerKey -What "Setting the writer key on $name"
    }
}

# --- Step 5: this repository's own settings ---------------------------------

Write-Section "Step 5/6  This repository's own settings"

$mergeSettings = [ordered]@{
    allow_merge_commit          = $false
    allow_rebase_merge          = $false
    allow_squash_merge          = $true
    squash_merge_commit_title   = 'PR_TITLE'
    squash_merge_commit_message = 'PR_BODY'
    allow_auto_merge            = $false
    delete_branch_on_merge      = $true
}
$different = @()
foreach ($key in $mergeSettings.Keys) {
    if ("$($repo.$key)" -ne "$($mergeSettings[$key])") { $different += $key }
}
if ($different.Count -eq 0) {
    Write-Ok 'squash-only merges, merged branches deleted'
}
else {
    Write-Change "set merge settings: $($different -join ', ')"
    if ($Apply) {
        $null = Invoke-Gh -Arguments @('api', '--method', 'PATCH', "repos/$Repository", '--input', '-') -InputText (ConvertTo-Json -InputObject $mergeSettings) -What 'Updating merge settings'
    }
}

if ($repo.visibility -eq 'public') {
    $scanning = $null
    $pushProtection = $null
    if ($null -ne $repo.security_and_analysis) {
        if ($null -ne $repo.security_and_analysis.secret_scanning) { $scanning = $repo.security_and_analysis.secret_scanning.status }
        if ($null -ne $repo.security_and_analysis.secret_scanning_push_protection) { $pushProtection = $repo.security_and_analysis.secret_scanning_push_protection.status }
    }
    if ($scanning -eq 'enabled' -and $pushProtection -eq 'enabled') {
        Write-Ok 'secret scanning and push protection are on'
    }
    else {
        Write-Change 'turn on secret scanning and push protection'
        if ($Apply) {
            $security = @{ security_and_analysis = @{ secret_scanning = @{ status = 'enabled' }; secret_scanning_push_protection = @{ status = 'enabled' } } }
            $null = Invoke-Gh -Arguments @('api', '--method', 'PATCH', "repos/$Repository", '--input', '-') -InputText (ConvertTo-Json -InputObject $security -Depth 5) -What 'Turning on secret scanning and push protection'
        }
    }
}
else {
    Write-Note 'The repository is not public, so secret scanning needs a licence; leave it to the org security configuration.'
}

Write-Change 'make sure Dependabot alerts and security updates are on'
if ($Apply) {
    $null = Invoke-Gh -Arguments @('api', '--method', 'PUT', "repos/$Repository/vulnerability-alerts") -What 'Turning on Dependabot alerts'
    $null = Invoke-Gh -Arguments @('api', '--method', 'PUT', "repos/$Repository/automated-security-fixes") -What 'Turning on Dependabot security updates'
}

# --- Step 6: ruleset on the default branch ----------------------------------

Write-Section 'Step 6/6  Ruleset on the default branch'

$ruleset = [ordered]@{
    name          = $rulesetName
    target        = 'branch'
    enforcement   = 'active'
    conditions    = @{ ref_name = @{ include = @('~DEFAULT_BRANCH'); exclude = @() } }
    # Org owners may merge a pull request without the approval (a solo owner
    # can't approve their own PR), but nobody pushes straight to main.
    bypass_actors = @(@{ actor_type = 'OrganizationAdmin'; bypass_mode = 'pull_request' })
    rules         = @(
        @{ type = 'deletion' },
        @{ type = 'non_fast_forward' },
        @{ type = 'required_linear_history' },
        @{
            type       = 'pull_request'
            parameters = [ordered]@{
                required_approving_review_count   = 1
                dismiss_stale_reviews_on_push     = $true
                require_code_owner_review         = $true
                require_last_push_approval        = $false
                required_review_thread_resolution = $true
                allowed_merge_methods             = @('squash')
            }
        },
        @{
            type       = 'required_status_checks'
            parameters = [ordered]@{
                strict_required_status_checks_policy = $true
                do_not_enforce_on_create             = $false
                required_status_checks               = @($RequiredChecks | ForEach-Object { @{ context = $_ } })
            }
        }
    )
}
$rulesetJson = ConvertTo-Json -InputObject $ruleset -Depth 10

$rulesets = @(Get-GhJson -Path "repos/$Repository/rulesets?per_page=100" -What 'Listing rulesets')
$existingRuleset = $rulesets | Where-Object { $null -ne $_ -and $_.name -eq $rulesetName -and $_.source_type -eq 'Repository' } | Select-Object -First 1
if ($null -eq $existingRuleset) {
    Write-Change "create ruleset $rulesetName (pull request with code-owner review; required checks: $($RequiredChecks -join ', '))"
    if ($Apply) {
        $null = Invoke-Gh -Arguments @('api', '--method', 'POST', "repos/$Repository/rulesets", '--input', '-') -InputText $rulesetJson -What "Creating ruleset $rulesetName"
    }
}
else {
    Write-Change "update ruleset $rulesetName (id $($existingRuleset.id)) to the standard definition; required checks: $($RequiredChecks -join ', ')"
    if ($Apply) {
        $null = Invoke-Gh -Arguments @('api', '--method', 'PUT', "repos/$Repository/rulesets/$($existingRuleset.id)", '--input', '-') -InputText $rulesetJson -What "Updating ruleset $rulesetName"
    }
}

# --- Summary ----------------------------------------------------------------

Write-Host ''
if ($Apply) {
    Write-Host "Done: $script:ChangeCount change(s) applied." -ForegroundColor Green
    Write-Host 'Next: generate and commit .terraform.lock.hcl, then open your first pull request (docs/setup.md, step 6).'
}
else {
    Write-Host "Dry run complete: $script:ChangeCount change(s) planned. Nothing was changed." -ForegroundColor Green
    Write-Host 'Read the [PLAN] lines above, then re-run the same command with -Apply.'
}
