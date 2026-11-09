# Supports: Claude Code (Windows / PowerShell 5.1+ and 7+)
<#
.SYNOPSIS
  Installs the Gwin shared rules into a project repo so every session (local or cloud) can read them.

.DESCRIPTION
  Run it inside a project (or pass -Project). It:
    1. Copies Gwin_Shared/instructions/*.md (except README.md) into <project>/.claude/gwin-shared/.
       Each copy starts with a one-line stamp: the source file, the Gwin_Shared commit, and a hash of the
       content, so a stale or hand-edited copy is easy to spot.
    2. Adds one marked block to <project>/CLAUDE.md that imports .claude/gwin-shared/RULES.md
       (creating CLAUDE.md if there is none). Nothing else in CLAUDE.md is touched.

  If the folder is not a git repo, or the repo has no GitHub remote, it warns that the rules will work
  only on this computer: Claude cloud sessions read the project from GitHub.

  It only previews by default; pass -Apply to write. It never commits or pushes: review the changes
  and commit them in the project like any other change. Re-run it to update the copies.

  A copy that was edited by hand, or a file in .claude/gwin-shared/ it didn't create, is left alone
  unless -Force is given.

  -Check writes nothing. It reports whether every rule can fire (rules loaded and committed, staging
  branch, HANDOFF.md, secrets setup, release notes, gh, model pins) as PASS, FIX, BLOCKED or ASK, and
  exits 1 if anything is not PASS.

.PARAMETER Project
  Path inside the project repo. Default: the current directory.

.PARAMETER Apply
  Write the changes. Without it, the script only shows what it would do.

.PARAMETER Force
  Overwrite or remove copies that were edited by hand, and files it didn't create.

.PARAMETER Uninstall
  Remove the copies and the CLAUDE.md block instead of installing.

.PARAMETER Check
  Check that every rule can fire. Read-only. Exit code 1 if any check is not PASS.

.PARAMETER Staging
  Name of the staging branch for -Check. Default: staging.

.EXAMPLE
  cd C:\code\MyProject; C:\code\Gwin_Shared\scripts\gwinrules.ps1
  C:\code\Gwin_Shared\scripts\gwinrules.ps1 -Project C:\code\MyProject -Apply
#>
[CmdletBinding()]
param(
    [string]$Project = (Get-Location).Path,
    [switch]$Apply,
    [switch]$Force,
    [switch]$Uninstall,
    [switch]$Check,
    [string]$Staging = 'staging'
)

$ErrorActionPreference = 'Stop'

$DestRel    = '.claude/gwin-shared'
$StartMark  = '<!-- gwin-shared:start -->'
$EndMark    = '<!-- gwin-shared:end -->'
$StampRegex = '^<!-- gwin-shared: file=(\S+) source=(\S+) sha256=([0-9a-f]{12}) '
$Utf8NoBom  = New-Object System.Text.UTF8Encoding($false)

function Read-Text([string]$Path) { [System.IO.File]::ReadAllText($Path, $Utf8NoBom) }
function Write-Text([string]$Path, [string]$Text) { [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom) }
function Normalize([string]$Text) { $Text.Replace("`r", '') }

function Get-ShortHash([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $bytes = $sha.ComputeHash($Utf8NoBom.GetBytes($Text)) } finally { $sha.Dispose() }
    (($bytes | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 12)
}

function Split-Stamped([string]$Text) {
    # Returns @{ Stamp = <match or $null>; Body = <text after the stamp line> }
    $t = Normalize $Text
    $nl = $t.IndexOf("`n")
    $first = if ($nl -ge 0) { $t.Substring(0, $nl) } else { $t }
    $m = [regex]::Match($first, $StampRegex)
    if (-not $m.Success) { return @{ Stamp = $null; Body = $t } }
    $body = if ($nl -ge 0) { $t.Substring($nl + 1) } else { '' }
    @{ Stamp = $m; Body = $body }
}

function Invoke-Git([string]$Dir, [string[]]$GitArgs) {
    $out = & git -C $Dir @GitArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    ($out -join "`n").Trim()
}

# --- Locate Gwin_Shared and the project -------------------------------------------------------

$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Src  = Join-Path $Repo 'instructions'

if (-not (Test-Path -LiteralPath $Project -PathType Container)) { throw "Folder not found: $Project" }
$root  = Invoke-Git $Project @('rev-parse', '--show-toplevel')
$IsGit = [bool]$root
$ProjectRoot = if ($IsGit) { (Resolve-Path $root).Path } else { (Resolve-Path $Project).Path }
if ($ProjectRoot -eq $Repo) { throw 'That is the Gwin_Shared repo itself; run this inside a project.' }
$homeDir = (Resolve-Path $HOME).Path
if (-not $IsGit -and ($ProjectRoot -eq $homeDir -or $ProjectRoot -eq [System.IO.Path]::GetPathRoot($ProjectRoot))) {
    throw "Refusing to install into $ProjectRoot (your home folder or a drive root). Run this inside a project folder."
}

$remotes   = if ($IsGit) { Invoke-Git $ProjectRoot @('remote', '-v') } else { $null }
$HasGitHub = [bool]($remotes -and ($remotes -match 'github\.com[:/]'))
$LocalOnly = $null
if (-not $IsGit) {
    $LocalOnly = @(
        'This folder is not a git repository.',
        'The rules will work only in this folder, on this computer.',
        'Claude cloud sessions and other computers will not see them.',
        'To share them: make the folder a git repo, add a GitHub remote, then commit and push.'
    ) -join "`n  "
} elseif (-not $HasGitHub) {
    $LocalOnly = @(
        'This repo has no GitHub remote.',
        'The rules will work only in copies of this repo on computers you set up yourself.',
        'Claude cloud sessions need the project on GitHub, so they will not see the rules.',
        'To share them: add a GitHub remote (git remote add origin <url>), then commit and push.'
    ) -join "`n  "
}
if ($LocalOnly) { Write-Warning "LOCAL ONLY`n  $LocalOnly" }

# --- -Check: can every rule fire? (read-only) --------------------------------------------------

if ($Check) {
    $script:Bad = 0
    function Add-Result([string]$Status, [string]$Name, [string]$Detail) {
        Write-Host ('  {0,-8} {1}' -f $Status, $Name)
        if ($Detail) { Write-Host "           $Detail" }
        if ($Status -ne 'PASS' -and $Status -ne 'INFO') { $script:Bad++ }
    }
    function Test-Cmd([string]$Name) { [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
    function Test-Git([string[]]$GitArgs) { & git -C $ProjectRoot @GitArgs 2>$null | Out-Null; $LASTEXITCODE -eq 0 }

    $cd = Join-Path $ProjectRoot $DestRel
    $prod = 'main'
    if ($IsGit) {
        $d = Invoke-Git $ProjectRoot @('symbolic-ref', '--short', 'refs/remotes/origin/HEAD')
        if ($d) { $prod = $d -replace '^origin/', '' }
    }
    Write-Host "Rule checks for $ProjectRoot (staging branch: $Staging, production branch: $prod)"
    Write-Host ''

    # Loaded (all rules)
    $missing = @(); $stale = @(); $ignored = @(); $untracked = @()
    foreach ($f in (Get-ChildItem -LiteralPath $Src -File -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' } | Sort-Object Name)) {
        $name = $f.Name
        $path = Join-Path $cd $name
        if (-not (Test-Path -LiteralPath $path)) { $missing += $name; continue }
        $h = Get-ShortHash (Normalize (Read-Text $f.FullName))
        $cur = Split-Stamped (Read-Text $path)
        if (-not $cur.Stamp -or $cur.Stamp.Groups[3].Value -ne $h -or (Get-ShortHash $cur.Body) -ne $h) { $stale += $name }
        if ($IsGit) {
            if (Test-Git @('check-ignore', '-q', "$DestRel/$name")) { $ignored += $name }
            if (-not (Test-Git @('ls-files', '--error-unmatch', "$DestRel/$name"))) { $untracked += $name }
        }
    }
    if ($missing) { Add-Result 'FIX' "rules: all rule files are in $DestRel" ("missing: $($missing -join ' '). Run gwinrules -Apply.") }
    elseif ($stale) { Add-Result 'FIX' 'rules: copies match Gwin_Shared' ("stale or edited: $($stale -join ' '). Run gwinrules -Apply.") }
    else { Add-Result 'PASS' "rules: all rule files are in $DestRel and match Gwin_Shared" '' }
    if ($ignored) { Add-Result 'FIX' 'rules: not ignored by git' ("ignored: $($ignored -join ' '). Remove or negate the .gitignore line.") }
    elseif ($IsGit -and -not $missing) { Add-Result 'PASS' 'rules: not ignored by git' '' }
    if (-not $IsGit) { Add-Result 'BLOCKED' 'rules: committed so cloud sessions can read them' 'Not a git repo.' }
    elseif ($untracked -and -not $missing) { Add-Result 'FIX' 'rules: committed' ("not tracked by git: $($untracked -join ' '). Commit and push them.") }
    elseif (-not $missing) { Add-Result 'PASS' 'rules: committed' '' }
    if (-not $HasGitHub) { Add-Result 'BLOCKED' 'rules: project has a GitHub remote' 'Cloud sessions read the project from GitHub.' }
    else { Add-Result 'PASS' 'rules: project has a GitHub remote' '' }
    $cm = Join-Path $ProjectRoot 'CLAUDE.md'
    if ((Test-Path -LiteralPath $cm) -and ((Read-Text $cm).Contains($StartMark)) -and ((Read-Text $cm).Contains("@$DestRel/RULES.md"))) { Add-Result 'PASS' 'rules: CLAUDE.md imports RULES.md' '' }
    else { Add-Result 'FIX' 'rules: CLAUDE.md imports RULES.md' 'Run gwinrules -Apply.' }
    Add-Result 'INFO' 'rules: loaded in a session' 'Start a new session and run /memory. All 12 rule files must show.'

    # Staging and protection (rules 02, 07)
    if ($IsGit) {
        $n = "branches: $Staging exists on origin (rules 02, 07)"
        if (Test-Git @('show-ref', '--verify', '-q', "refs/remotes/origin/$Staging")) { Add-Result 'PASS' $n '' }
        elseif (Test-Git @('show-ref', '--verify', '-q', "refs/heads/$Staging")) { Add-Result 'BLOCKED' $n 'It exists only on this computer. Push it.' }
        else { Add-Result 'BLOCKED' $n "Create it from $prod, push it, protect it. If you just created it, run git fetch." }
    }
    $ghOk = $HasGitHub -and (Test-Cmd 'gh')
    if ($ghOk) { & gh auth status 2>$null | Out-Null; $ghOk = ($LASTEXITCODE -eq 0) }
    if ($ghOk) {
        Push-Location $ProjectRoot
        try {
            foreach ($b in @($Staging, $prod)) {
                & gh api "repos/{owner}/{repo}/branches/$b/protection" 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { Add-Result 'PASS' "branches: $b is protected (rules 02, 07)" '' }
                else { Add-Result 'BLOCKED' "branches: $b is protected (rules 02, 07)" 'No branch protection rule found. Rulesets are not visible here; confirm in GitHub settings.' }
            }
            $dob = (& gh repo view --json deleteBranchOnMerge -q .deleteBranchOnMerge 2>$null)
            if ($LASTEXITCODE -ne 0) { $dob = 'unknown' }
            if ("$dob" -eq 'true') { Add-Result 'PASS' 'branches: Automatically delete head branches is on (rule 07)' '' }
            else { Add-Result 'BLOCKED' 'branches: Automatically delete head branches is on (rule 07)' "Turn it on in GitHub settings (value: $dob). Protect $Staging and $prod first." }
        } finally { Pop-Location }
    } else {
        Add-Result 'BLOCKED' 'branches: protection and auto-delete (rules 02, 07)' "Cannot confirm. Check in GitHub settings: $Staging and $prod protected against deletion and force-push; Automatically delete head branches on."
    }

    # Handoff (rules 03, 08)
    $hf = Join-Path $ProjectRoot 'HANDOFF.md'
    if (-not (Test-Path -LiteralPath $hf)) { Add-Result 'FIX' 'handoff: HANDOFF.md exists (rules 03, 08)' 'Install the pipeline kit, or create a minimal HANDOFF.md.' }
    else {
        $ht = Read-Text $hf
        if ($ht -match '(?i)last updated[*_: ]*\d{4}-\d{2}-\d{2}') { Add-Result 'PASS' 'handoff: has a Last updated date' '' }
        else { Add-Result 'FIX' 'handoff: has a Last updated date' 'Add: **Last updated:** YYYY-MM-DD' }
        if ($ht -match '(?i)divergence:') { Add-Result 'PASS' 'handoff: has a Divergence line' '' }
        else { Add-Result 'FIX' 'handoff: has a Divergence line' 'Add: **Divergence:** <branch state>' }
    }

    # Secrets (rule 04). Never reads .env files.
    $gi = Join-Path $ProjectRoot '.gitignore'
    if ((Test-Path -LiteralPath $gi) -and ((Read-Text $gi) -match '(?m)^/?\.env(\*|\.local|\.\*)?[ \t]*\r?$')) { Add-Result 'PASS' 'secrets: .env is in .gitignore (rule 04)' '' }
    else { Add-Result 'FIX' 'secrets: .env is in .gitignore (rule 04)' 'Add .env and .env.local to .gitignore.' }
    if (Test-Path -LiteralPath (Join-Path $ProjectRoot '.env.example')) { Add-Result 'PASS' 'secrets: .env.example exists' '' }
    else { Add-Result 'FIX' 'secrets: .env.example exists' 'Create it with placeholder values only.' }
    $sj = Join-Path $ProjectRoot '.claude/settings.json'
    $denyOk = $false
    if (Test-Path -LiteralPath $sj) {
        try {
            $deny = @((Read-Text $sj | ConvertFrom-Json).permissions.deny)
            $denyOk = [bool]($deny | Where-Object { $_ -and $_.StartsWith('Read(') -and $_.Contains('.env') })
        } catch { $denyOk = $false }
    }
    if ($denyOk) { Add-Result 'PASS' 'secrets: settings.json denies reading .env' '' }
    else { Add-Result 'FIX' 'secrets: settings.json denies reading .env' 'Add Read(./.env) and Read(./.env.*) to permissions.deny in .claude/settings.json.' }

    # Release notes and PR checklist files (rule 05)
    if (Get-ChildItem -LiteralPath $ProjectRoot -File -Filter 'CHANGELOG*' -ErrorAction SilentlyContinue) { Add-Result 'PASS' 'release notes: CHANGELOG exists (rule 05)' '' }
    else { Add-Result 'FIX' 'release notes: CHANGELOG exists (rule 05)' 'Create CHANGELOG.md, or name another file in CLAUDE.md.' }
    $ver = @('package.json', 'pyproject.toml', 'Cargo.toml', 'VERSION', 'version.txt', 'setup.py', '.claude-plugin/plugin.json') | Where-Object { Test-Path -LiteralPath (Join-Path $ProjectRoot $_) }
    if ($ver) { Add-Result 'PASS' 'release notes: version source found' "found: $($ver -join ' ')" }
    else { Add-Result 'ASK' 'release notes: version source found' 'Tell me where the version lives.' }
    if (Test-Path -LiteralPath (Join-Path $ProjectRoot 'claude/design-doc-index.md')) { Add-Result 'PASS' 'pr checklist: design-doc index exists' '' }
    else { Add-Result 'FIX' 'pr checklist: design-doc index exists' 'Create claude/design-doc-index.md (the pipeline kit does this).' }
    function Find-Named([string]$Pattern) {
        $rootLen = $ProjectRoot.Length
        [bool](Get-ChildItem -LiteralPath $ProjectRoot -Recurse -Depth 2 -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like $Pattern -and $_.FullName.Substring($rootLen) -notmatch '[\\/](\.git|node_modules)([\\/]|$)' } | Select-Object -First 1)
    }
    if (Find-Named '*architecture*') { Add-Result 'PASS' 'pr checklist: architecture diagram found' '' }
    else { Add-Result 'ASK' 'pr checklist: architecture diagram found' 'Name the diagram file, or say there is none.' }
    if (Find-Named '*regression*') { Add-Result 'PASS' 'pr checklist: regression list found' '' }
    else { Add-Result 'ASK' 'pr checklist: regression list found' 'Name the regression list, or say there is none.' }

    # Tools (rules 01, 11) and model tiers (rule 06)
    if (Test-Cmd 'gh') {
        & gh auth status 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { Add-Result 'PASS' 'tools: gh installed and signed in' '' }
        else { Add-Result 'FIX' 'tools: gh installed and signed in' 'Run gh auth login yourself. Never paste a token into chat.' }
    } else { Add-Result 'FIX' 'tools: gh installed and signed in' "Install gh. Without it, read CI on the PR's Checks tab." }
    if ((Test-Cmd 'python3') -or (Test-Cmd 'python')) { Add-Result 'PASS' 'tools: python available' '' }
    else { Add-Result 'FIX' 'tools: python available' "The pipeline kit's tools need Python 3." }
    $agents = @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot '.claude/agents') -File -Filter '*.md' -ErrorAction SilentlyContinue)
    if ($agents -and ($agents | Select-String -Pattern '^model: ' -Quiet)) { Add-Result 'PASS' 'model tiers: agent files pin a model (rule 06)' '' }
    else { Add-Result 'ASK' 'model tiers: agent files pin a model (rule 06)' 'Install the kit, or say which model fills each tier.' }
    Add-Result 'INFO' 'test command' 'Rules 01 and 05 need one. Set TEST_COMMAND in the kit interview, or say there is none.'
    Add-Result 'INFO' 'rule 10' 'Applies only if test suites share live data or accounts.'
    Write-Host ''
    Write-Host 'Checks do not enforce rules. Only settings.json permissions and hooks enforce.'
    if ($script:Bad -eq 0) { Write-Host 'All rule checks passed.'; exit 0 }
    Write-Host "$($script:Bad) check(s) not PASS. Fix them, then re-run with -Check."
    exit 1
}

$commit = Invoke-Git $Repo @('rev-parse', '--short', 'HEAD')
if (-not $commit) { $commit = 'unknown' }
$dirty = Invoke-Git $Repo @('status', '--porcelain', '--', 'instructions')
$source = "gwincode/Gwin_Shared@$commit"
if ($dirty) {
    $source += '+local'
    Write-Warning 'Gwin_Shared/instructions has uncommitted changes; copies will be stamped "+local". Commit them in Gwin_Shared first for a clean stamp.'
}

$Dest       = Join-Path $ProjectRoot $DestRel
$ClaudeMd   = Join-Path $ProjectRoot 'CLAUDE.md'
$sources    = @(Get-ChildItem -LiteralPath $Src -File -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' } | Sort-Object Name)
if (-not $sources) { throw "No rule files found in $Src" }
$sourceNames = $sources | ForEach-Object { $_.Name }

Write-Host "Gwin_Shared: $Repo ($source)"
Write-Host "Project:     $ProjectRoot"
Write-Host ''

$actions = New-Object System.Collections.Generic.List[object]   # @{ Kind; Path; Text }
function Add-Action([string]$Kind, [string]$Path, [string]$Note, [string]$Text) {
    $actions.Add(@{ Kind = $Kind; Path = $Path; Text = $Text })
    $rel = $Path.Substring($ProjectRoot.Length).TrimStart('\', '/')
    $line = '  {0,-8} {1}' -f $Kind, $rel
    if ($Note) { $line += "  ($Note)" }
    Write-Host $line
}

# --- Rule copies -------------------------------------------------------------------------------

Write-Host "$DestRel/"
if (-not $Uninstall) {
    foreach ($s in $sources) {
        $body  = Normalize (Read-Text $s.FullName)
        $hash  = Get-ShortHash $body
        $stamp = "<!-- gwin-shared: file=$($s.Name) source=$source sha256=$hash | Managed by gwinrules: edit in Gwin_Shared and re-run, not here. -->"
        $text  = "$stamp`n$body"
        $path  = Join-Path $Dest $s.Name

        if (-not (Test-Path -LiteralPath $path)) { Add-Action 'add' $path '' $text; continue }
        $cur = Split-Stamped (Read-Text $path)
        if (-not $cur.Stamp) {
            if ($Force) { Add-Action 'replace' $path 'not created by gwinrules; -Force' $text }
            else { Write-Warning "skip $($s.Name): exists but wasn't created by gwinrules (use -Force to replace)" }
            continue
        }
        $edited = (Get-ShortHash $cur.Body) -ne $cur.Stamp.Groups[3].Value
        if ($cur.Body -ceq $body -and -not $edited) { Write-Host ('  {0,-8} {1}' -f 'same', "$DestRel/$($s.Name)"); continue }
        if ($edited -and -not $Force) { Write-Warning "skip $($s.Name): edited by hand since it was installed (use -Force to overwrite)"; continue }
        Add-Action 'update' $path $(if ($edited) { 'overwriting local edits' } else { '' }) $text
    }
}

if (Test-Path -LiteralPath $Dest) {
    foreach ($f in Get-ChildItem -LiteralPath $Dest -File) {
        if (-not $Uninstall -and $sourceNames -contains $f.Name) { continue }
        $cur = Split-Stamped (Read-Text $f.FullName)
        if (-not $cur.Stamp) {
            if ($Force) { Add-Action 'remove' $f.FullName 'not created by gwinrules; -Force' $null }
            else { Write-Warning "keep $($f.Name): not created by gwinrules" }
            continue
        }
        $edited = (Get-ShortHash $cur.Body) -ne $cur.Stamp.Groups[3].Value
        if ($edited -and -not $Force) { Write-Warning "keep $($f.Name): edited by hand (use -Force to remove)"; continue }
        Add-Action 'remove' $f.FullName $(if ($Uninstall) { '' } else { 'no longer in Gwin_Shared' }) $null
    }
}

# --- CLAUDE.md block ---------------------------------------------------------------------------

Write-Host 'CLAUDE.md'
$block = @(
    $StartMark,
    '## Shared rules',
    '',
    'This project follows the Gwin shared rules, installed by `gwinrules` from Gwin_Shared. Edit them in',
    'Gwin_Shared and re-run `gwinrules`, not here. A rule in this file overrides a shared rule only where it',
    'says so explicitly.',
    '',
    "@$DestRel/RULES.md",
    $EndMark
) -join "`n"

$claudeExists = Test-Path -LiteralPath $ClaudeMd
$orig = if ($claudeExists) { Read-Text $ClaudeMd } else { '' }
$crlf = $orig.Contains("`r`n")
$text = Normalize $orig
$si = $text.IndexOf($StartMark)
$ei = $text.IndexOf($EndMark)
$newText = $null

if (($si -ge 0) -xor ($ei -ge 0) -or ($si -ge 0 -and $ei -lt $si)) {
    Write-Warning 'CLAUDE.md has a broken gwin-shared block (one marker missing or out of order); fix it by hand. CLAUDE.md left unchanged.'
} elseif ($Uninstall) {
    if ($si -ge 0) {
        $before = $text.Substring(0, $si).TrimEnd("`n")
        $after  = $text.Substring($ei + $EndMark.Length).TrimStart("`n")
        if (-not $before) { $newText = $after }
        elseif ($after) { $newText = "$before`n`n$after" }
        else { $newText = "$before`n" }
    } else { Write-Host '  none     (no block to remove)' }
} elseif ($si -ge 0) {
    $newText = $text.Substring(0, $si) + $block + $text.Substring($ei + $EndMark.Length)
} elseif ($claudeExists) {
    $newText = $text.TrimEnd("`n") + "`n`n" + $block + "`n"
} else {
    $newText = "$block`n"
}

if ($null -ne $newText) {
    if ($crlf) { $newText = $newText.Replace("`n", "`r`n") }
    if ($newText -ceq $orig) { Write-Host '  same     CLAUDE.md' }
    elseif ($Uninstall -and -not $newText.Trim()) { Add-Action 'remove' $ClaudeMd 'only held the shared-rules block' $null }
    else {
        $kind = if (-not $claudeExists) { 'create' } elseif ($Uninstall) { 'edit' } elseif ($si -ge 0) { 'update' } else { 'append' }
        Add-Action $kind $ClaudeMd $(if ($Uninstall) { 'remove the shared-rules block' } else { 'shared-rules import block' }) $newText
    }
}

# --- Apply -------------------------------------------------------------------------------------

Write-Host ''
if ($LocalOnly) { Write-Warning "LOCAL ONLY`n  $LocalOnly" }
if (-not $actions.Count) { Write-Host 'Nothing to change.'; return }
if (-not $Apply) { Write-Host "Preview only: $($actions.Count) change(s). Re-run with -Apply to write them."; return }

if (-not $Uninstall -and -not (Test-Path -LiteralPath $Dest)) { New-Item -ItemType Directory -Path $Dest -Force | Out-Null }
foreach ($a in $actions) {
    if ($a.Kind -eq 'remove') { Remove-Item -LiteralPath $a.Path -Force }
    else { Write-Text $a.Path $a.Text }
}
if ($Uninstall -and (Test-Path -LiteralPath $Dest) -and -not (Get-ChildItem -LiteralPath $Dest -Force)) {
    Remove-Item -LiteralPath $Dest -Force
}
Write-Host "Wrote $($actions.Count) change(s). Nothing was committed."
if ($IsGit) {
    Write-Host "Review with: git -C `"$ProjectRoot`" status"
    if ($HasGitHub) { Write-Host 'Commit and push the changes so that cloud sessions and other computers get them.' }
}
