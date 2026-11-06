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

.PARAMETER Target
  Config folder to install into. Default: ~/.claude

.PARAMETER Copy
  Copy everything instead of linking.

.PARAMETER Force
  Replace existing items that are not links into this repo.

.PARAMETER Uninstall
  Remove links (and copies with matching names) that this script installed.

.EXAMPLE
  ./scripts/install.ps1 -WhatIf
  ./scripts/install.ps1
  ./scripts/install.ps1 -Target C:\code\MyProject\.claude
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Target = (Join-Path $HOME '.claude'),
    [switch]$Copy,
    [switch]$Force,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

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
    }
}

$sets = @(
    @{ Name = 'skills';   Dirs = $true  },
    @{ Name = 'agents';   Dirs = $false },
    @{ Name = 'commands'; Dirs = $false }
)

Write-Host "Repo:   $Repo"
Write-Host "Target: $Target"

foreach ($set in $sets) {
    $srcRoot = Join-Path $Repo $set.Name
    $dstRoot = Join-Path $Target $set.Name
    if (-not (Test-Path -LiteralPath $srcRoot)) { continue }

    $items = if ($set.Dirs) {
        Get-ChildItem -LiteralPath $srcRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }
    } else {
        Get-ChildItem -LiteralPath $srcRoot -File -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' }
    }
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
