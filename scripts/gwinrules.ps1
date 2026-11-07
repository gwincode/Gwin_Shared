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

.PARAMETER Project
  Path inside the project repo. Default: the current directory.

.PARAMETER Apply
  Write the changes. Without it, the script only shows what it would do.

.PARAMETER Force
  Overwrite or remove copies that were edited by hand, and files it didn't create.

.PARAMETER Uninstall
  Remove the copies and the CLAUDE.md block instead of installing.

.EXAMPLE
  cd C:\code\MyProject; C:\code\Gwin_Shared\scripts\gwinrules.ps1
  C:\code\Gwin_Shared\scripts\gwinrules.ps1 -Project C:\code\MyProject -Apply
#>
[CmdletBinding()]
param(
    [string]$Project = (Get-Location).Path,
    [switch]$Apply,
    [switch]$Force,
    [switch]$Uninstall
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
