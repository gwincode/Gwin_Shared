# Supports: Claude Code (Windows / PowerShell 5.1+ and 7+)
<#
.SYNOPSIS
  Links shared skills, agents and commands from this repo into a Claude Code config folder.

.DESCRIPTION
  skills/<name>/      -> <Target>/skills/<name>      (directory junction; no admin needed)
  agents/<name>.md    -> <Target>/agents/<name>.md   (symlink, or copy if symlinks are not allowed)
  commands/<name>.md  -> <Target>/commands/<name>.md (symlink, or copy if symlinks are not allowed)

  README.md files are ignored. Existing items that are not links into this repo are left alone
  unless -Force is given. File symlinks on Windows need Developer Mode or an elevated shell;
  without them the script copies the file and says so. Copies do not update on `git pull`;
  refresh them with -Force (which also replaces any other item with the same name).

  Also installs the token status line (plugins/cc-token-statusline, MIT, Alfafis) into the personal
  ~/.claude only. It backs up settings.json and chains onto any status line already set. Skip it with
  -NoStatusline. With -Target it is skipped, because a status line is a personal setting.

  -Loader shows progress with the ASCII loader (scripts/ascii-loader-lib.ps1): one step per item,
  [ OK ] / [SKIP] / [FAIL] per line, and a stop on the first failure. Each step's own output is
  captured and its last line is shown as a note. Link steps are quick and run in-process, so only the
  status line step animates. Without -Loader the output is the plain list, which is what you want in
  CI and logs. Under -WhatIf, -Loader prints plain lines so the "What if" text does not fight the
  animation.

.PARAMETER Target
  Config folder to install into. Default: ~/.claude

.PARAMETER Copy
  Copy everything instead of linking.

.PARAMETER Force
  Replace existing items that are not links into this repo.

.PARAMETER Uninstall
  Remove links (and copies with matching names) that this script installed. Also removes the
  token status line and restores the status line that was there before.

.PARAMETER NoStatusline
  Do not install the token status line.

.PARAMETER Loader
  Show progress with the ASCII loader.

.EXAMPLE
  ./scripts/install.ps1 -WhatIf
  ./scripts/install.ps1
  ./scripts/install.ps1 -Loader
  ./scripts/install.ps1 -Target C:\code\MyProject\.claude
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Target = (Join-Path $HOME '.claude'),
    [switch]$Copy,
    [switch]$Force,
    [switch]$Uninstall,
    [switch]$NoStatusline,
    [switch]$Loader
)

$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$PersonalTarget = Join-Path $HOME '.claude'
$script:LoaderSkip = $false   # set by a step that was skipped, so -Loader can show [SKIP]

function Get-LinkTarget([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType) { return [string]($item.Target | Select-Object -First 1) }
    return $null
}

function Test-PointsIntoRepo([string]$Path) {
    $t = Get-LinkTarget $Path
    return [bool]($t -and $t.StartsWith($Repo, [StringComparison]::OrdinalIgnoreCase))
}

function Remove-Existing([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.LinkType) {
        # Delete the link itself, never what it points to.
        if ($item.PSIsContainer) { [System.IO.Directory]::Delete($Path) } else { [System.IO.File]::Delete($Path) }
    } else {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Install-Item([string]$Source, [string]$Dest, [bool]$IsDir) {
    $exists = Test-Path -LiteralPath $Dest
    if ($exists) {
        if (Test-PointsIntoRepo $Dest) {
            if (-not $Copy) { Write-Host "  ok       $Dest"; return }
        } elseif (-not $Force) {
            Write-Warning "skip     $Dest (exists and is not a link into this repo; use -Force to replace)"
            $script:LoaderSkip = $true
            return
        }
        if ($PSCmdlet.ShouldProcess($Dest, 'Replace')) { Remove-Existing $Dest }
    }

    if (-not $PSCmdlet.ShouldProcess($Dest, "Install from $Source")) { return }

    if ($Copy) {
        Copy-Item -LiteralPath $Source -Destination $Dest -Recurse -Force
        Write-Host "  copied   $Dest"
    } elseif ($IsDir) {
        New-Item -ItemType Junction -Path $Dest -Target $Source | Out-Null
        Write-Host "  linked   $Dest"
    } else {
        try {
            New-Item -ItemType SymbolicLink -Path $Dest -Target $Source -ErrorAction Stop | Out-Null
            Write-Host "  linked   $Dest"
        } catch {
            Copy-Item -LiteralPath $Source -Destination $Dest -Force
            Write-Host "  copied   $Dest (symlink not permitted; enable Developer Mode to link files)"
        }
    }
}

function Uninstall-Item([string]$Source, [string]$Dest) {
    if (-not (Test-Path -LiteralPath $Dest)) { return }
    if ((Test-PointsIntoRepo $Dest) -or $Force) {
        if ($PSCmdlet.ShouldProcess($Dest, 'Remove')) { Remove-Existing $Dest; Write-Host "  removed  $Dest" }
    } else {
        Write-Warning "keep     $Dest (not a link into this repo; use -Force to remove copies)"
        $script:LoaderSkip = $true
    }
}

$sets = @(
    @{ Name = 'skills';   Dirs = $true  },
    @{ Name = 'agents';   Dirs = $false },
    @{ Name = 'commands'; Dirs = $false }
)

# The items this repo ships in one set. Skills are folders with a SKILL.md; agents and commands are
# .md files other than README.md.
function Get-SetItems($Set) {
    $srcRoot = Join-Path $Repo $Set.Name
    if ($Set.Dirs) {
        Get-ChildItem -LiteralPath $srcRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }
    } else {
        Get-ChildItem -LiteralPath $srcRoot -File -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' }
    }
}

# What the status line step will do: run the plugin's installer, or skip with a reason.
function Get-StatuslinePlan {
    if ($NoStatusline) { return @{ Run = $false; Reason = 'skipped (-NoStatusline)' } }
    if ($Target -ne $PersonalTarget) {
        return @{ Run = $false; Reason = 'skipped (only the personal ~/.claude gets a status line, not -Target)' }
    }
    # Prefer the py launcher: a bare "python" can be a Microsoft Store stub that prints an ad.
    $exe = $null; $pre = @()
    if (Get-Command py -ErrorAction SilentlyContinue) { $exe = 'py'; $pre = @('-3') }
    elseif (Get-Command python -ErrorAction SilentlyContinue) { $exe = 'python' }
    if (-not $exe) {
        return @{ Run = $false; Warn = $true; Reason = 'skipped (Python 3 not found; the badge needs it)' }
    }
    $a = @($pre) + @((Join-Path $Repo 'plugins/cc-token-statusline/scripts/install.py'))
    if ($Uninstall) { $a += '--uninstall' }
    elseif ($WhatIfPreference) { $a += '--dry-run' }
    return @{ Run = $true; Exe = $exe; Args = $a }
}

# ---- -Loader: one step per item, plus one for the status line -----------------------------------
if ($Loader) {
    . (Join-Path $PSScriptRoot 'ascii-loader-lib.ps1')

    $work = @()
    foreach ($set in $sets) {
        if (-not (Test-Path -LiteralPath (Join-Path $Repo $set.Name))) { continue }
        foreach ($i in @(Get-SetItems $set)) {
            $kind = switch ($set.Name) { 'skills' { 'skill' } 'agents' { 'agent' } default { 'command' } }
            $label = if ($kind -eq 'skill') { $i.Name } else { $i.Name -replace '\.md$', '' }
            $work += [pscustomobject]@{
                Set = $set; Item = $i; Label = "${kind}: $label"
                Dest = Join-Path (Join-Path $Target $set.Name) $i.Name
            }
        }
    }
    $plan = Get-StatuslinePlan
    $verb = if ($Uninstall) { 'Removing' } else { 'Installing' }
    $title = "Gwin_Shared -> $Target"
    if ($WhatIfPreference) { $title += ' (what if: nothing is changed)' }
    Initialize-Loader -Title $title -Total ($work.Count + 1) -Verb $verb -NoAnim:$WhatIfPreference

    $ok = $true
    foreach ($w in $work) {
        $ok = Invoke-LoaderBlock -Label $w.Label -ScriptBlock {
            $dstRoot = Join-Path $Target $w.Set.Name
            if (-not $Uninstall -and -not (Test-Path -LiteralPath $dstRoot) -and
                $PSCmdlet.ShouldProcess($dstRoot, 'Create folder')) {
                New-Item -ItemType Directory -Path $dstRoot -Force | Out-Null
            }
            if ($Uninstall) { Uninstall-Item $w.Item.FullName $w.Dest }
            else { Install-Item $w.Item.FullName $w.Dest $w.Set.Dirs }
        }
        if (-not $ok) { break }
    }
    if ($ok) {
        if ($plan.Run) {
            # The plugin's installer reads CLAUDE_CONFIG_DIR; set it for this step only.
            $PrevConfigDir = $env:CLAUDE_CONFIG_DIR
            $env:CLAUDE_CONFIG_DIR = $Target
            try { $ok = Invoke-LoaderStep -Label 'token status line' -FilePath $plan.Exe -ArgumentList $plan.Args }
            finally { $env:CLAUDE_CONFIG_DIR = $PrevConfigDir }
        } else {
            $ok = Invoke-LoaderBlock -Label 'token status line' -ScriptBlock {
                $script:LoaderSkip = $true
                Write-Output "statusline: $($plan.Reason)"
            }
        }
    }
    if (Complete-Loader) { exit 0 } else { exit 1 }
}

# ---- default: the plain list --------------------------------------------------------------------
Write-Host "Repo:   $Repo"
Write-Host "Target: $Target"

foreach ($set in $sets) {
    $srcRoot = Join-Path $Repo $set.Name
    $dstRoot = Join-Path $Target $set.Name
    if (-not (Test-Path -LiteralPath $srcRoot)) { continue }

    $items = Get-SetItems $set
    if (-not $items) { Write-Host "$($set.Name): nothing to do"; continue }

    Write-Host "$($set.Name):"
    if (-not $Uninstall -and -not (Test-Path -LiteralPath $dstRoot) -and $PSCmdlet.ShouldProcess($dstRoot, 'Create folder')) {
        New-Item -ItemType Directory -Path $dstRoot -Force | Out-Null
    }
    foreach ($i in $items) {
        $dest = Join-Path $dstRoot $i.Name
        if ($Uninstall) { Uninstall-Item $i.FullName $dest } else { Install-Item $i.FullName $dest $set.Dirs }
    }
}

$plan = Get-StatuslinePlan
if (-not $plan.Run) {
    if ($plan.Warn) { Write-Warning "statusline: $($plan.Reason)" } else { Write-Host "statusline: $($plan.Reason)" }
} else {
    Write-Host 'statusline:'
    $PrevConfigDir = $env:CLAUDE_CONFIG_DIR
    $env:CLAUDE_CONFIG_DIR = $Target   # the plugin's installer reads this
    try {
        & $plan.Exe @($plan.Args)
        if ($LASTEXITCODE -ne 0) { Write-Warning 'statusline: installer failed (links above are unaffected)' }
    } finally {
        $env:CLAUDE_CONFIG_DIR = $PrevConfigDir
    }
}
