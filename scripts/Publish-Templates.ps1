#Requires -Version 5.1
<#
.SYNOPSIS
    Publishes templates/ to the repositories it describes, in one environment's org.

.DESCRIPTION
    READ-ONLY UNLESS YOU ADD -Apply. Without -Apply the script compares every
    file under templates/ with what the org's repository holds and prints the
    result for each: Create, Update, No change, Unmanaged, Off or Blocked.

    With -Apply it proposes the differences as ONE pull request per repository,
    which you review and merge like any other change. It never pushes to a
    default branch and never deletes a file: a file in GitHub that templates/
    doesn't hold is reported as Unmanaged and left alone.

    What gets published, and the values filled in for {{PLACEHOLDERS}}, are in
    templates/templates.json. {{ORGANIZATION}} is the environment's org and
    {{PLATFORM_REPOSITORY}} this repository. A repository switched off there
    ("enabled": false) is checked and shown as Off, never published.

    Rules it enforces:
      * Sandbox first. Any other environment is refused until the sandbox
        already holds the same files, published and merged.
      * Only what is merged is published: with -Apply, your checkout must be
        main, up to date with origin, with no local changes under templates/.
      * One publish at a time per repository: an open publish pull request
        blocks the next one until it is merged or closed.

    Where to run: Windows PowerShell 5.1 or PowerShell 7, from the repository
    root, with gh signed in as an owner of the org. Publishing workflow files
    needs the workflow scope: gh auth refresh --scopes workflow

.EXAMPLE
    .\scripts\Publish-Templates.ps1 -Environment sandbox            # dry run
    .\scripts\Publish-Templates.ps1 -Environment sandbox -Apply     # opens the pull requests

    Merge them, then do the same with -Environment prod.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive console script: the coloured status lines are its output.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z][a-z0-9-]*$')]
    [string] $Environment,

    # Publish only these repositories (names from templates.json). Default: all.
    [string[]] $Repository,

    [ValidatePattern('^[a-z][a-z0-9-]*$')]
    [string] $SandboxEnvironment = 'sandbox',

    [switch] $Apply
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false # exit codes are checked explicitly below
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { $null = $_ }
$OutputEncoding = New-Object System.Text.UTF8Encoding $false

$configPath = Join-Path 'templates' 'templates.json'
$branchPrefix = 'publish-templates-'
$utf8 = New-Object System.Text.UTF8Encoding $false

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

function Exit-Publish([string] $Text) {
    Write-Host ''
    Write-Host "STOPPED: $Text" -ForegroundColor Red
    Write-Host 'Nothing after this point was changed.' -ForegroundColor Red
    exit 1
}

# --- gh helpers -------------------------------------------------------------

function Invoke-Gh {
    param(
        [Parameter(Mandatory = $true)] [string[]] $Arguments,
        [Parameter(Mandatory = $true)] [string] $What,
        [string] $InputText
    )
    # Windows PowerShell 5.1 drops double quotes inside arguments passed to a
    # program, so gh would get a different --jq filter. Keep them out.
    foreach ($argument in $Arguments) {
        if ($argument.Contains('"')) { Exit-Publish "Script bug: a gh argument contains a double quote, which Windows PowerShell 5.1 removes: $argument" }
    }
    if ($PSBoundParameters.ContainsKey('InputText')) {
        $output = $InputText | & gh @Arguments
    }
    else {
        $output = & gh @Arguments
    }
    if ($LASTEXITCODE -ne 0) {
        Exit-Publish "$What failed (gh exit code $LASTEXITCODE). The gh message above says why."
    }
    return (@($output) -join "`n")
}

# Lines of text from a gh call that uses --jq, without parsing JSON in
# PowerShell (Windows PowerShell 5.1 does not unroll JSON arrays reliably).
function Get-GhLines {
    param(
        [Parameter(Mandatory = $true)] [string[]] $Arguments,
        [Parameter(Mandatory = $true)] [string] $What
    )
    $text = Invoke-Gh -Arguments $Arguments -What $What
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($text -split "`n")) {
        if ($line.Trim().Length -gt 0) { $lines.Add($line.Trim()) }
    }
    return , $lines
}

function Invoke-GhPost {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [object] $Body,
        [Parameter(Mandatory = $true)] [string] $Field,
        [Parameter(Mandatory = $true)] [string] $What
    )
    $json = ConvertTo-Json -InputObject $Body -Depth 10 -Compress
    $value = Invoke-Gh -Arguments @('api', '--method', 'POST', $Path, '--input', '-', '--jq', $Field) -InputText $json -What $What
    if ([string]::IsNullOrWhiteSpace($value)) { Exit-Publish "$What returned no $Field." }
    return $value.Trim()
}

# --- Reading config and templates -------------------------------------------

function Get-EnvironmentOrg([string] $Name) {
    $file = Join-Path 'environments' "$Name.tfvars"
    if (-not (Test-Path -Path $file -PathType Leaf)) {
        Exit-Publish "$file not found. -Environment must match a file in environments\."
    }
    $match = Select-String -Path $file -Pattern '^\s*github_org\s*=\s*"([^"]+)"' | Select-Object -First 1
    if ($null -eq $match) { Exit-Publish "github_org is not set in $file." }
    return $match.Matches[0].Groups[1].Value
}

# Every file under a template folder, as path => content, with placeholders
# filled in. Text is compared and published with LF line endings.
function Get-RenderedFiles {
    param(
        [Parameter(Mandatory = $true)] [string] $Source,
        [Parameter(Mandatory = $true)] [hashtable] $Values
    )
    $root = (Resolve-Path -Path $Source).ProviderPath
    $files = [ordered]@{}
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($item in (Get-ChildItem -Path $root -Recurse -File -Force | Sort-Object FullName)) {
        $relative = $item.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
        $text = [System.IO.File]::ReadAllText($item.FullName, $utf8).Replace("`r`n", "`n")
        $evaluator = {
            param($m)
            $name = $m.Groups[1].Value
            if ($Values.ContainsKey($name) -and -not [string]::IsNullOrWhiteSpace([string]$Values[$name])) {
                return [string]$Values[$name]
            }
            if (-not $missing.Contains($name)) { $missing.Add($name) }
            return $m.Value
        }.GetNewClosure()
        # {{NAME}} in capitals; never a GitHub expression such as ${{ github.ref }}.
        $files[$relative] = [regex]::Replace($text, '(?<!\$)\{\{([A-Z][A-Z0-9_]*)\}\}', $evaluator)
    }
    if ($files.Count -eq 0) { Exit-Publish "$Source holds no files." }
    return [pscustomobject]@{ Files = $files; Missing = @($missing) }
}

# Compares one template with its repository in one org. Reads only.
function Get-TemplatePlan {
    param(
        [Parameter(Mandatory = $true)] [string] $Org,
        [Parameter(Mandatory = $true)] [object] $Entry,
        [Parameter(Mandatory = $true)] [hashtable] $Values,
        [Parameter(Mandatory = $true)] [string[]] $OrgRepositories
    )
    $name = [string]$Entry.name
    $plan = [pscustomobject]@{
        Name          = $name
        Org           = $Org
        Enabled       = ($Entry.enabled -ne $false)
        Blocked       = $null
        DefaultBranch = $null
        Rows          = New-Object System.Collections.Generic.List[object]
        Changes       = [ordered]@{}
        Unmanaged     = New-Object System.Collections.Generic.List[string]
    }

    $source = Join-Path 'templates' ([string]$Entry.source)
    if (-not (Test-Path -Path $source -PathType Container)) { Exit-Publish "templates.json names $source, which does not exist." }
    $orgValues = @{}
    foreach ($key in $Values.Keys) { $orgValues[$key] = $Values[$key] }
    $orgValues['ORGANIZATION'] = $Org
    $rendered = Get-RenderedFiles -Source $source -Values $orgValues

    if ($rendered.Missing.Count -gt 0) {
        $plan.Blocked = "No value for $($rendered.Missing -join ', ') in templates.json. Fill it in, or keep this repository switched off."
        if ($plan.Enabled) { return $plan }
    }
    if ($OrgRepositories -notcontains $name) {
        $how = "Create it first: gh repo create $Org/$name --public"
        if ($name -ne '.github') { $how = 'Terraform creates it: merge the change that adds it to platform.auto.tfvars, and let the apply finish' }
        $plan.Blocked = "$Org/$name does not exist. $how."
        return $plan
    }

    $plan.DefaultBranch = (Invoke-Gh -Arguments @('api', "repos/$Org/$name", '--jq', '.default_branch') -What "Reading $Org/$name").Trim()
    $truncated = (Invoke-Gh -Arguments @('api', "repos/$Org/$name/git/trees/$($plan.DefaultBranch)?recursive=1", '--jq', '.truncated') -What "Listing the files in $Org/$name").Trim()
    if ($truncated -ne 'false') { Exit-Publish "GitHub truncated the file list of $Org/$name, so the comparison would be incomplete." }
    $entries = Get-GhLines -Arguments @('api', "repos/$Org/$name/git/trees/$($plan.DefaultBranch)?recursive=1", '--jq', '.tree[] | [.type, .path] | @tsv') -What "Listing the files in $Org/$name"
    $existing = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $entries) {
        $fields = $entry -split "`t", 2
        if ($fields.Count -ne 2) { Exit-Publish "Unexpected file list entry from $Org/${name}: $entry" }
        if ($fields[0] -eq 'blob') { $existing.Add($fields[1]) }
    }

    foreach ($path in $rendered.Files.Keys) {
        $wanted = $rendered.Files[$path]
        if ($existing -notcontains $path) {
            $plan.Rows.Add([pscustomobject]@{ Path = $path; Result = 'Create' })
            $plan.Changes[$path] = $wanted
            continue
        }
        $encoded = Invoke-Gh -Arguments @('api', "repos/$Org/$name/contents/$($path)?ref=$($plan.DefaultBranch)", '--jq', '.content') -What "Reading $path in $Org/$name"
        $current = $utf8.GetString([Convert]::FromBase64String(($encoded -replace '\s', ''))).Replace("`r`n", "`n")
        if ($current -ceq $wanted) {
            $plan.Rows.Add([pscustomobject]@{ Path = $path; Result = 'No change' })
        }
        else {
            $plan.Rows.Add([pscustomobject]@{ Path = $path; Result = 'Update' })
            $plan.Changes[$path] = $wanted
        }
    }
    foreach ($path in $existing) {
        if (-not $rendered.Files.Contains($path)) { $plan.Unmanaged.Add($path) }
    }

    if ($plan.Enabled -and $plan.Changes.Count -gt 0) {
        $pullRequests = Get-GhLines -Arguments @('pr', 'list', '--repo', "$Org/$name", '--state', 'open', '--limit', '100', '--json', 'number,headRefName', '--jq', '.[] | [.number, .headRefName] | @tsv') -What "Listing open pull requests in $Org/$name"
        $open = New-Object System.Collections.Generic.List[string]
        foreach ($entry in $pullRequests) {
            $fields = $entry -split "`t", 2
            if ($fields.Count -ne 2) { Exit-Publish "Unexpected pull request entry from $Org/${name}: $entry" }
            if ($fields[1].StartsWith($branchPrefix, [System.StringComparison]::Ordinal)) { $open.Add($fields[0]) }
        }
        if ($open.Count -gt 0) {
            $plan.Blocked = "An earlier publish is still open: pull request #$($open[0]) in $Org/$name. Merge or close it, then publish again."
        }
    }
    return $plan
}

function Show-Plan([object] $Plan) {
    $state = 'On'
    if (-not $Plan.Enabled) { $state = 'Off (switched off in templates.json: checked, never published)' }
    Write-Host ''
    Write-Host "   $($Plan.Org)/$($Plan.Name)  [$state]" -ForegroundColor White
    foreach ($row in $Plan.Rows) {
        $colour = 'Gray'
        if ($row.Result -ne 'No change') { $colour = 'Yellow' }
        Write-Host ('     {0,-10} {1}' -f $row.Result, $row.Path) -ForegroundColor $colour
    }
    foreach ($path in $Plan.Unmanaged) {
        Write-Host ('     {0,-10} {1}  (in GitHub only: reported, never removed)' -f 'Unmanaged', $path) -ForegroundColor DarkGray
    }
    if ($null -ne $Plan.Blocked) { Write-Host "     Blocked:   $($Plan.Blocked)" -ForegroundColor Red }
}

# Opens one pull request with every change, as a single commit on a new branch.
function Publish-Plan([object] $Plan, [string] $SourceCommit) {
    $org = $Plan.Org
    $name = $Plan.Name
    $head = (Invoke-Gh -Arguments @('api', "repos/$org/$name/git/ref/heads/$($Plan.DefaultBranch)", '--jq', '.object.sha') -What "Reading $($Plan.DefaultBranch) in $org/$name").Trim()
    $baseTree = (Invoke-Gh -Arguments @('api', "repos/$org/$name/git/commits/$head", '--jq', '.tree.sha') -What "Reading commit $head in $org/$name").Trim()

    $tree = New-Object System.Collections.Generic.List[object]
    foreach ($path in $Plan.Changes.Keys) {
        $content = [Convert]::ToBase64String($utf8.GetBytes([string]$Plan.Changes[$path]))
        $blob = Invoke-GhPost -Path "repos/$org/$name/git/blobs" -Body @{ content = $content; encoding = 'base64' } -Field '.sha' -What "Uploading $path to $org/$name"
        $tree.Add(@{ path = $path; mode = '100644'; type = 'blob'; sha = $blob })
    }
    $newTree = Invoke-GhPost -Path "repos/$org/$name/git/trees" -Body @{ base_tree = $baseTree; tree = $tree.ToArray() } -Field '.sha' -What "Building the new file tree for $org/$name"
    $message = "Publish templates from $script:PlatformRepository@$SourceCommit"
    $commit = Invoke-GhPost -Path "repos/$org/$name/git/commits" -Body @{ message = $message; tree = $newTree; parents = @($head) } -Field '.sha' -What "Committing to $org/$name"
    $branch = $branchPrefix + (Get-Date -Format 'yyyyMMdd-HHmmss')
    $null = Invoke-GhPost -Path "repos/$org/$name/git/refs" -Body @{ ref = "refs/heads/$branch"; sha = $commit } -Field '.ref' -What "Creating branch $branch in $org/$name (publishing workflow files needs: gh auth refresh --scopes workflow)"

    $body = New-Object System.Text.StringBuilder
    $null = $body.AppendLine("Files published from templates/$((Split-Path -Leaf ([string]$Plan.Source))) in $script:PlatformRepository at $SourceCommit.")
    $null = $body.AppendLine('')
    $null = $body.AppendLine('| Result | File |')
    $null = $body.AppendLine('|---|---|')
    foreach ($row in $Plan.Rows) {
        if ($row.Result -ne 'No change') { $null = $body.AppendLine("| $($row.Result) | ``$($row.Path)`` |") }
    }
    $null = $body.AppendLine('')
    $null = $body.AppendLine("Change these files in $script:PlatformRepository, not here: the next publish would propose undoing an edit made here.")
    $bodyFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($bodyFile, $body.ToString(), $utf8)
        $url = Invoke-Gh -Arguments @('pr', 'create', '--repo', "$org/$name", '--base', $Plan.DefaultBranch, '--head', $branch, '--title', "Publish templates from $script:PlatformRepository", '--body-file', $bodyFile) -What "Opening the pull request in $org/$name"
    }
    finally {
        Remove-Item -Path $bodyFile -Force
    }
    Write-Ok "Pull request opened: $($url.Trim())"
}

# --- Prerequisites (read-only) ----------------------------------------------

Write-Host ''
if ($Apply) {
    Write-Host 'Mode: APPLY. Pull requests will be opened.' -ForegroundColor Yellow
}
else {
    Write-Host 'Mode: DRY RUN (read-only). Nothing will be changed. Add -Apply to open the pull requests.' -ForegroundColor Green
}

Write-Section 'Checking prerequisites (read-only)'

if (-not (Test-Path -Path $configPath -PathType Leaf) -or -not (Test-Path -Path 'environments' -PathType Container)) {
    Exit-Publish 'Run this from the repository root (the folder that contains templates\ and environments\).'
}
if ($null -eq (Get-Command -Name gh -ErrorAction SilentlyContinue)) { Exit-Publish 'The GitHub CLI (gh) is not installed: https://cli.github.com' }
if ($null -eq (Get-Command -Name git -ErrorAction SilentlyContinue)) { Exit-Publish 'git is not installed.' }

$me = (Invoke-Gh -Arguments @('api', 'user', '--jq', '.login') -What 'Checking who gh is signed in as (run gh auth login if this fails)').Trim()
$script:PlatformRepository = (Invoke-Gh -Arguments @('repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner') -What 'Finding this repository on GitHub').Trim()
Write-Ok "gh is signed in as $me; this repository is $script:PlatformRepository"

$config = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText((Resolve-Path $configPath).ProviderPath, $utf8))
$values = @{}
foreach ($property in $config.values.PSObject.Properties) { $values[$property.Name] = [string]$property.Value }
$values['PLATFORM_REPOSITORY'] = $script:PlatformRepository
$entries = New-Object System.Collections.Generic.List[object]
foreach ($entry in $config.repositories) {
    if ($null -eq $Repository -or $Repository -contains [string]$entry.name) { $entries.Add($entry) }
}
if ($entries.Count -eq 0) { Exit-Publish "No repository in templates.json matches -Repository $($Repository -join ', ')." }

$sourceCommit = (& git rev-parse --short HEAD)
if ($LASTEXITCODE -ne 0) { Exit-Publish 'This folder is not a git checkout.' }
$localChanges = @(& git status --porcelain -- templates)
if ($LASTEXITCODE -ne 0) { Exit-Publish 'git status failed.' }
if ($Apply) {
    $branchName = (& git rev-parse --abbrev-ref HEAD)
    & git fetch --quiet origin main
    if ($LASTEXITCODE -ne 0) { Exit-Publish 'git fetch origin main failed.' }
    $behind = (& git rev-parse HEAD) -ne (& git rev-parse origin/main)
    if ($branchName -ne 'main' -or $behind) { Exit-Publish "Publish only what is merged: git switch main, then git pull. (You are on $branchName at $sourceCommit.)" }
    if ($localChanges.Count -gt 0) { Exit-Publish 'templates\ has local changes. Commit them through a pull request first, or discard them.' }
}
elseif ($localChanges.Count -gt 0) {
    Write-Note 'templates\ has local changes: this dry run shows them, but -Apply publishes only what is merged on main.'
}

$org = Get-EnvironmentOrg $Environment
$orgRepositories = Get-GhLines -Arguments @('repo', 'list', $org, '--limit', '1000', '--json', 'name', '--jq', '.[].name') -What "Listing the repositories in $org"
Write-Ok "Environment $Environment is org $org ($($orgRepositories.Count) repositories)"

# --- Sandbox first ----------------------------------------------------------

if ($Environment -ne $SandboxEnvironment) {
    Write-Section "Sandbox first: checking $SandboxEnvironment (read-only)"
    $sandboxOrg = Get-EnvironmentOrg $SandboxEnvironment
    $sandboxRepositories = Get-GhLines -Arguments @('repo', 'list', $sandboxOrg, '--limit', '1000', '--json', 'name', '--jq', '.[].name') -What "Listing the repositories in $sandboxOrg"
    foreach ($entry in $entries) {
        if ($entry.enabled -eq $false) { continue }
        $sandboxPlan = Get-TemplatePlan -Org $sandboxOrg -Entry $entry -Values $values -OrgRepositories $sandboxRepositories
        if ($null -ne $sandboxPlan.Blocked -or $sandboxPlan.Changes.Count -gt 0) {
            Show-Plan $sandboxPlan
            Exit-Publish "$sandboxOrg/$($entry.name) does not hold the current templates yet. Publish to $SandboxEnvironment and merge its pull request first."
        }
        Write-Ok "$sandboxOrg/$($entry.name) already holds the current templates"
    }
}

# --- Plan -------------------------------------------------------------------

Write-Section "Comparing templates/ with $org (read-only)"
$plans = New-Object System.Collections.Generic.List[object]
foreach ($entry in $entries) {
    $plan = Get-TemplatePlan -Org $org -Entry $entry -Values $values -OrgRepositories $orgRepositories
    $plan | Add-Member -NotePropertyName Source -NotePropertyValue ([string]$entry.source)
    Show-Plan $plan
    $plans.Add($plan)
}

$toPublish = @($plans | Where-Object { $_.Enabled -and $null -eq $_.Blocked -and $_.Changes.Count -gt 0 })
$blocked = @($plans | Where-Object { $_.Enabled -and $null -ne $_.Blocked })

if ($blocked.Count -gt 0) {
    Exit-Publish "$($blocked.Count) repository(s) blocked. The Blocked lines above say what to do."
}
if ($toPublish.Count -eq 0) {
    Write-Host ''
    Write-Host "Everything switched on in templates.json is already published in $org." -ForegroundColor Green
    exit 0
}
if (-not $Apply) {
    Write-Host ''
    Write-Host "Dry run: $($toPublish.Count) pull request(s) would be opened. Run the same command with -Apply." -ForegroundColor Green
    exit 0
}

# --- Apply ------------------------------------------------------------------

Write-Section "Opening pull requests in $org"
foreach ($plan in $toPublish) {
    Publish-Plan -Plan $plan -SourceCommit $sourceCommit
}
Write-Host ''
Write-Host 'Review and merge each pull request. Publish again afterwards: every file should show No change.' -ForegroundColor Green
