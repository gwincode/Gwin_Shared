# Supports: Windows PowerShell 5.1+ and PowerShell 7+ (Windows; also macOS / Linux with pwsh). Tool-agnostic.
<#
.SYNOPSIS
  Lo-fi ASCII progress loader for install-style work: a little face, a bouncing bar for the
  running step, and a permanent checklist of finished steps. A failed step stops the run and
  prints the tail of its log.

.DESCRIPTION
  The drawing code lives in ascii-loader-lib.ps1, which other scripts (such as install.ps1 -Loader)
  dot-source directly.

  Animation needs ANSI escape support: PowerShell 7 or Windows Terminal. Elsewhere (older
  conhost, redirected output, CI) it falls back to plain lines. Use -NoAnim to force plain output.

  Steps file: one step per line, "Label | command". Lines starting with # are ignored.
  Each command runs in a separate PowerShell process, so keep one command per line. A line without
  " | " is rejected before anything runs.

.PARAMETER Demo
  Simulated install (Start-Sleep only). Changes nothing.

.PARAMETER DemoFail
  Simulated install where step 3 fails.

.PARAMETER StepsFile
  Run the steps in this file.

.PARAMETER NoAnim
  Plain output, no animation.

.EXAMPLE
  scripts\ascii-loader.ps1 -Demo
#>
[CmdletBinding()]
param(
    [switch]$Demo,
    [switch]$DemoFail,
    [string]$StepsFile,
    [switch]$NoAnim
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ascii-loader-lib.ps1')

# ---- build the step list ------------------------------------------------------------------
$Steps = @()
if ($Demo -or $DemoFail) {
    $Steps += @{ Label = 'Checking prerequisites'; Cmd = 'Start-Sleep -Seconds 1' }
    $Steps += @{ Label = 'Downloading packages';   Cmd = 'Start-Sleep -Seconds 2' }
    if ($DemoFail) {
        $Steps += @{ Label = 'Unpacking files'; Cmd = 'Write-Output "tar: unexpected end of file"; [Console]::Error.WriteLine("checksum mismatch on pkg-2.3.tgz"); exit 2' }
        $Steps += @{ Label = 'Linking config';  Cmd = 'Start-Sleep -Seconds 1' }
    } else {
        $Steps += @{ Label = 'Unpacking files';     Cmd = 'Start-Sleep -Milliseconds 1500' }
        $Steps += @{ Label = 'Linking config';      Cmd = 'Start-Sleep -Milliseconds 800' }
        $Steps += @{ Label = 'Verifying checksums'; Cmd = 'Start-Sleep -Seconds 1' }
    }
} elseif ($StepsFile) {
    if (-not (Test-Path -LiteralPath $StepsFile)) { throw "no such steps file: $StepsFile" }
    # Check every line before running anything: a typo must not turn into a command.
    $n = 0
    foreach ($line in Get-Content -LiteralPath $StepsFile) {
        $n++
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $parts = $t -split ' \| ', 2
        if ($parts.Count -ne 2) { throw "$StepsFile line ${n}: expected 'Label | command', got: $t" }
        if (-not $parts[0].Trim() -or -not $parts[1].Trim()) {
            throw "$StepsFile line ${n}: label and command must both be non-empty"
        }
        $Steps += @{ Label = $parts[0].Trim(); Cmd = $parts[1].Trim() }
    }
} else {
    Get-Help $PSCommandPath -Detailed | Out-Host
    return
}

if ($Steps.Count -eq 0) { throw 'no steps to run' }

Initialize-Loader -Title 'ascii-loader' -Total $Steps.Count -NoAnim:$NoAnim
foreach ($s in $Steps) {
    if (-not (Invoke-LoaderStep -Label $s.Label -Command $s.Cmd)) { break }
}
if (Complete-Loader) { exit 0 } else { exit 1 }
