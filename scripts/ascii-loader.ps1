# Supports: Windows PowerShell 5.1+ and PowerShell 7+ (Windows; also macOS / Linux with pwsh). Tool-agnostic.
<#
.SYNOPSIS
  Lo-fi ASCII progress loader for install-style work: a little face, a bouncing bar for the
  running step, and a permanent checklist of finished steps. A failed step stops the run and
  prints the tail of its log.

.DESCRIPTION
  Animation needs ANSI escape support: PowerShell 7 or Windows Terminal. Elsewhere (older
  conhost, redirected output, CI) it falls back to plain lines. Use -NoAnim to force plain output.

  Steps file: one step per line, "Label | command". Lines starting with # are ignored.
  Each command runs in a separate PowerShell process, so keep one command per line.

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
$E = [char]27
$Anim = (-not $NoAnim) -and (-not [Console]::IsOutputRedirected) -and `
        ($PSVersionTable.PSVersion.Major -ge 7 -or $env:WT_SESSION)

if ($Anim) {
  $G = "$E[32m"; $R = "$E[31m"; $C = "$E[36m"; $D = "$E[2m"; $B = "$E[1m"; $N = "$E[0m"
} else {
  $G = ''; $R = ''; $C = ''; $D = ''; $B = ''; $N = ''
}

$BarW      = 24
$LiveLines = 5
$LiveDrawn = $false
$LogDir    = Join-Path ([IO.Path]::GetTempPath()) ("ascii-loader-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $LogDir | Out-Null
$PwshExe   = if ($PSVersionTable.PSVersion.Major -ge 6) { (Get-Process -Id $PID).Path } else { 'powershell.exe' }

function Clear-Live {
  if ($Anim -and $script:LiveDrawn) {
    # \r first: "cursor up" keeps the column, so return to column 0 before moving up.
    [Console]::Write("`r$E[$($LiveLines)A$E[J")
  }
  $script:LiveDrawn = $false
}

function Write-Live([string]$face, [string]$headline, [string]$bar, [string]$footer) {
  if (-not $Anim) { return }
  Write-Host "   .-----.   $headline"
  Write-Host "   | $face |   $bar"
  Write-Host "   |  ~  |   $footer"
  Write-Host "   '-----'"
  Write-Host ''
  $script:LiveDrawn = $true
}

function Get-Bounce([int]$pos) {
  $s = -join (0..($BarW - 1) | ForEach-Object { if ($_ -ge $pos -and $_ -lt ($pos + 4)) { '=' } else { '.' } })
  "[$s]"
}

function Get-Full([int]$done, [int]$total) {
  $f = [math]::Floor($done * $BarW / $total)
  $s = -join (0..($BarW - 1) | ForEach-Object { if ($_ -lt $f) { '#' } else { '.' } })
  "[$s]"
}

function Invoke-Step([int]$idx, [int]$total, [string]$label, [string]$cmd) {
  $log = Join-Path $LogDir "step$idx.log"
  $err = Join-Path $LogDir "step$idx.err"
  $start = Get-Date
  # Start-Process joins -ArgumentList with spaces and does not quote them, so a command with
  # spaces and quotes would be split apart. -EncodedCommand (base64 UTF-16) passes it intact.
  # The prefix turns off ANSI colour in the child's output so the log files stay readable.
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(
               "if (`$PSStyle) { `$PSStyle.OutputRendering = 'PlainText' }; $cmd"))
  $proc = Start-Process -FilePath $PwshExe -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded) `
            -RedirectStandardOutput $log -RedirectStandardError $err -PassThru -NoNewWindow

  $pos = 0; $dir = 1; $tick = 0
  $spin = @('|', '/', '-', '\')
  if ($Anim) { [Console]::Write("$E[?25l") }   # hide cursor while animating
  try {
    while (-not $proc.HasExited) {
      if ($Anim) {
        Clear-Live
        Write-Live 'o_o' "$($C)$($B)Installing$($N) $label" (Get-Bounce $pos) `
                   "$($D)step $idx of $total  $($spin[$tick % 4])  working...$($N)"
        $pos += $dir
        if ($pos -ge ($BarW - 4)) { $dir = -1 }
        if ($pos -le 0) { $dir = 1 }
        $tick++
      }
      Start-Sleep -Milliseconds 120
    }
    $proc.WaitForExit()
  } finally {
    if ($Anim) { [Console]::Write("$E[?25h") }  # always restore the cursor
  }

  $rc = $proc.ExitCode
  $elapsed = [int]((Get-Date) - $start).TotalSeconds
  Clear-Live
  if ($rc -eq 0) {
    Write-Host "   $($G)[ OK ]$($N) $label $($D)($($elapsed)s)$($N)"
  } else {
    Write-Host "   $($R)[FAIL]$($N) $label $($D)(exit $rc)$($N)"
    Write-Host "   $($D)last lines of $($log):$($N)"
    $tail = @()
    foreach ($f in @($log, $err)) { if (Test-Path $f) { $tail += Get-Content $f -Tail 5 } }
    $tail | Select-Object -Last 5 | ForEach-Object { Write-Host "      | $_" }
  }
  return $rc
}

# ---- build the step list ------------------------------------------------------------------
$Steps = @()
if ($Demo -or $DemoFail) {
  $Steps += @{ Label = 'Checking prerequisites'; Cmd = 'Start-Sleep -Seconds 1' }
  $Steps += @{ Label = 'Downloading packages';   Cmd = 'Start-Sleep -Seconds 2' }
  if ($DemoFail) {
    $Steps += @{ Label = 'Unpacking files'; Cmd = 'Write-Output "tar: unexpected end of file"; [Console]::Error.WriteLine("checksum mismatch on pkg-2.3.tgz"); exit 2' }
    $Steps += @{ Label = 'Linking config'; Cmd = 'Start-Sleep -Seconds 1' }
  } else {
    $Steps += @{ Label = 'Unpacking files';      Cmd = 'Start-Sleep -Milliseconds 1500' }
    $Steps += @{ Label = 'Linking config';       Cmd = 'Start-Sleep -Milliseconds 800' }
    $Steps += @{ Label = 'Verifying checksums';  Cmd = 'Start-Sleep -Seconds 1' }
  }
} elseif ($StepsFile) {
  if (-not (Test-Path $StepsFile)) { throw "no such steps file: $StepsFile" }
  foreach ($line in Get-Content $StepsFile) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $parts = $t -split ' \| ', 2
    if ($parts.Count -ne 2) { throw "bad step line (want 'Label | command'): $t" }
    $Steps += @{ Label = $parts[0]; Cmd = $parts[1] }
  }
} else {
  Get-Help $PSCommandPath -Detailed | Out-Host
  return
}

$Total = $Steps.Count
if ($Total -eq 0) { throw 'no steps to run' }

Write-Host ''
Write-Host "   $($B)ascii-loader$($N)  $($D)$Total step(s)$($N)"
Write-Host ''

$Done = 0; $Idx = 0; $Failed = $false
$StartAll = Get-Date
if ($Anim) { Write-Live '-_-' "$($D)Getting ready...$($N)" (Get-Full 0 $Total) "$($D)0 of $Total done$($N)" }

foreach ($s in $Steps) {
  $Idx++
  $rc = Invoke-Step $Idx $Total $s.Label $s.Cmd
  if ($rc -ne 0) { $Failed = $true; break }
  $Done++
  if ($Anim -and $Done -lt $Total) {
    Write-Live '^_^' "$($G)Step done$($N)" (Get-Full $Done $Total) "$($D)$Done of $Total done$($N)"
  }
}

Clear-Live
$Elapsed = [int]((Get-Date) - $StartAll).TotalSeconds
Write-Host ''
if (-not $Failed) {
  Write-Live '^_^' "$($G)$($B)All done$($N)" (Get-Full $Done $Total) "$($G)$Done of $Total installed in $($Elapsed)s$($N)"
  Write-Host "   $($G)$($B)SUCCESS$($N)  nothing left to install."
  exit 0
} else {
  Write-Live 'x_x' "$($R)$($B)Stopped$($N)" (Get-Full $Done $Total) "$($R)$Done of $Total installed, step $Idx failed$($N)"
  Write-Host "   $($R)$($B)FAILED$($N)  fix the step above and run again."
  Write-Host "   $($D)logs kept in $LogDir$($N)"
  exit 1
}
