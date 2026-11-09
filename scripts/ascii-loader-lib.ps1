# Supports: Windows PowerShell 5.1+ and PowerShell 7+ (Windows; also macOS / Linux with pwsh). Tool-agnostic.
# This is a library: dot-source it (`. .\ascii-loader-lib.ps1`) from a script file. For a command line,
# use ascii-loader.ps1.
#
# Lo-fi ASCII progress loader. A step's output goes to a log, not the screen. The screen shows a small
# face, a bouncing bar for the running step, and a permanent checklist of finished steps.
#
# API
#   Initialize-Loader -Title T -Total N [-Verb 'Installing'] [-NoAnim]
#       Call once, before any step. Total is the number of steps to come.
#   Invoke-LoaderStep -Label L -Command 'powershell text'        (or)
#   Invoke-LoaderStep -Label L -FilePath exe -ArgumentList a,b
#       Run an external process as one step, animated while it runs. Exit 0 is [ OK ], exit 10 is
#       [SKIP] (counts as success), anything else is [FAIL]. -Command runs in a child PowerShell.
#   Invoke-LoaderBlock -Label L -ScriptBlock { ... }
#       Run a script block in this process as one step. It is not animated (a block cannot run in the
#       background in this session), so use it for quick work. Everything it writes is captured and its
#       last line becomes the note. A thrown error is [FAIL]. To report [SKIP], set $script:LoaderSkip
#       to $true inside the block.
#   Complete-Loader
#       Print the summary. Returns $true if every step passed, $false otherwise.
#
# Behaviour
#   - After a failure, later steps do nothing and return $false.
#   - Animation needs ANSI escapes: PowerShell 7 or Windows Terminal, on a real terminal. Elsewhere
#     (older conhost, redirected output, TERM=dumb, -NoAnim) the output is plain lines. NO_COLOR turns
#     colours off.
#   - Ctrl-C stops the running step, restores the cursor, and removes the logs.
#   - Logs are removed on success. After a failure their folder is kept and named.

$script:LD = @{
    Anim = $false; Cols = 80; Live = $false; LiveLines = 5; BarW = 24
    Total = 0; Idx = 0; Done = 0; Skipped = 0; Failed = $false
    Title = ''; Verb = 'Installing'; Dir = $null; Start = $null; Esc = [char]27
}
$script:LDC = @{ G = ''; R = ''; Y = ''; C = ''; D = ''; B = ''; N = '' }
$script:LoaderSkip = $false
$script:LDPwsh = if ($PSVersionTable.PSVersion.Major -ge 6) { (Get-Process -Id $PID).Path } else { 'powershell.exe' }

function Limit-LoaderText([string]$Text, [int]$Max) {
    if ($Max -lt 1) { $Max = 1 }
    if ($Text.Length -le $Max) { return $Text }
    if ($Max -le 3) { return $Text.Substring(0, $Max) }
    return $Text.Substring(0, $Max - 3) + '...'
}

function Get-LoaderBounceBar([int]$Pos) {
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $script:LD.BarW; $i++) {
        if ($i -ge $Pos -and $i -lt ($Pos + 4)) { [void]$sb.Append('=') } else { [void]$sb.Append('.') }
    }
    return '[' + $sb.ToString() + ']'
}

function Get-LoaderFullBar([int]$Done) {
    $w = $script:LD.BarW
    $filled = if ($script:LD.Total -gt 0) { [int][math]::Floor($Done * $w / $script:LD.Total) } else { 0 }
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $w; $i++) { if ($i -lt $filled) { [void]$sb.Append('#') } else { [void]$sb.Append('.') } }
    return '[' + $sb.ToString() + ']'
}

# Move back to the top of the live block and wipe it, so it can be redrawn in place.
function Clear-LoaderLive {
    $ld = $script:LD
    if ($ld.Anim -and $ld.Live) {
        # `r first: "cursor up" keeps the column, so return to column 0 before moving up.
        [Console]::Write("`r$($ld.Esc)[$($ld.LiveLines)A$($ld.Esc)[J")
    }
    $ld.Live = $false
}

function Write-LoaderLive([string]$Face, [string]$Verb, [string]$VerbColor, [string]$Label,
                          [string]$Bar, [string]$Footer, [string]$FootColor) {
    $c = $script:LDC; $cols = $script:LD.Cols
    # Everything is cut to fit: a label that wraps makes the block taller than the cursor-up count.
    $max = $cols - 15 - $Verb.Length
    if ($max -lt 8) { $max = 8 }
    $lab  = Limit-LoaderText $Label $max
    $foot = Limit-LoaderText $Footer ($cols - 15)
    Write-Host "   .-----.   $VerbColor$Verb$($c.N) $lab"
    Write-Host "   | $Face |   $Bar"
    Write-Host "   |  ~  |   $FootColor$foot$($c.N)"
    Write-Host "   '-----'"
    Write-Host ''
    $script:LD.Live = $true
}

function Get-LoaderLines([string]$Text) {
    return @($Text -split "`r?`n" |
        ForEach-Object { ($_ -replace '\x1b\[[0-9;?]*[A-Za-z]', '').Trim() } |
        Where-Object { $_ })
}

# Tidy a note so the useful part survives truncation: squeeze padding, and show the home folder as ~.
function Format-LoaderNote([string]$Note) {
    $n = $Note -replace ' {2,}', ' '
    if ($HOME) { $n = $n.Replace($HOME, '~') }
    return $n
}

function Write-LoaderResult([string]$Tag, [string]$Label, [int]$Secs, [string]$Note) {
    $c = $script:LDC; $cols = $script:LD.Cols
    # Budget: "   [ OK ] " is 10 columns, plus one spare so a full line never wraps. The time tail is
    # measured first, the label gets what is left, and the note only gets room the label did not use.
    $tail = if ($Secs -ge 1) { " (${Secs}s)" } else { '' }
    $l = Limit-LoaderText $Label ($cols - 11 - $tail.Length)
    $room = $cols - 11 - $l.Length - $tail.Length - 4          # 4 = the "  - " before the note
    $n = ''
    if ($Note -and $room -ge 8) { $n = "  $($c.D)- $(Limit-LoaderText $Note $room)$($c.N)" }
    if ($tail) { $tail = "$($c.D)$tail$($c.N)" }
    Write-Host "   $Tag $l$tail$n"
}

function Remove-LoaderDir {
    $d = $script:LD.Dir
    if ($d -and (Split-Path -Leaf $d) -like 'ascii-loader-*' -and (Test-Path -LiteralPath $d)) {
        Remove-Item -LiteralPath $d -Recurse -Force -WhatIf:$false -ErrorAction SilentlyContinue
    }
}

function Initialize-Loader {
    param([string]$Title, [int]$Total, [string]$Verb = 'Installing', [switch]$NoAnim)
    $ld = $script:LD; $c = $script:LDC
    $ld.Title = $Title; $ld.Total = $Total; $ld.Verb = $Verb
    $ld.Idx = 0; $ld.Done = 0; $ld.Skipped = 0; $ld.Failed = $false; $ld.Live = $false
    $ld.Start = Get-Date

    $ld.Anim = (-not $NoAnim) -and (-not [Console]::IsOutputRedirected) -and ($env:TERM -ne 'dumb') -and
               ($PSVersionTable.PSVersion.Major -ge 7 -or [bool]$env:WT_SESSION)
    foreach ($k in @($c.Keys)) { $c[$k] = '' }
    if ($ld.Anim -and -not $env:NO_COLOR) {
        $e = $ld.Esc
        $c.G = "$e[32m"; $c.R = "$e[31m"; $c.Y = "$e[33m"; $c.C = "$e[36m"
        $c.D = "$e[2m";  $c.B = "$e[1m";  $c.N = "$e[0m"
    }
    # Width matters: a label that wraps makes the live block taller than the cursor-up count. Ask the
    # console first ([Console]::WindowWidth is right on pseudo-terminals, where RawUI.WindowSize can
    # report a stale 80), then the host, then fall back to 80.
    $ld.Cols = 80
    if ($ld.Anim) {
        $w = 0
        try { $w = [Console]::WindowWidth } catch { }
        if ($w -lt 1) { try { $w = $Host.UI.RawUI.WindowSize.Width } catch { } }
        if ($w -ge 1) { $ld.Cols = $w }
    }
    if ($ld.Cols -lt 40) { $ld.Cols = 40 }

    $ld.Dir = Join-Path ([IO.Path]::GetTempPath()) ('ascii-loader-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    # -WhatIf:$false on every cmdlet this library calls: the preference is inherited from the caller,
    # and a caller's -WhatIf must change what the caller installs, not the loader's own bookkeeping.
    [void](New-Item -ItemType Directory -Path $ld.Dir -WhatIf:$false)

    Write-Host ''
    Write-Host "   $($c.B)$(Limit-LoaderText $Title ($ld.Cols - 20))$($c.N)  $($c.D)$Total step(s)$($c.N)"
    Write-Host ''
    if ($ld.Anim) {
        Write-LoaderLive '-_-' 'Getting ready' $c.D '' (Get-LoaderFullBar 0) "0 of $Total done" $c.D
    }
}

# Shared by both step kinds: print the result line, update counters, redraw the live block.
# $Rc is the step's exit code (0 ok, 10 skip, else fail). Returns $true unless the step failed.
function Complete-LoaderStep([string]$Label, [int]$Rc, [double]$Secs, [string]$Text) {
    $ld = $script:LD; $c = $script:LDC
    # @() is not optional: a function that returns one line hands back a bare string, and $lines[-1]
    # on a string is its last character.
    $lines = @(Get-LoaderLines $Text)
    $note = if ($lines.Count) { Format-LoaderNote $lines[-1] } else { '' }
    $secs = [int]$Secs
    if ($Rc -eq 0) {
        Write-LoaderResult "$($c.G)[ OK ]$($c.N)" $Label $secs $note
    } elseif ($Rc -eq 10) {
        Write-LoaderResult "$($c.Y)[SKIP]$($c.N)" $Label $secs $note
        $ld.Skipped++
    } else {
        Write-LoaderResult "$($c.R)[FAIL]$($c.N)" $Label $secs "exit $Rc"
        Write-Host "   $($c.D)last lines of its log:$($c.N)"
        $lines | Select-Object -Last 5 | ForEach-Object {
            Write-Host "      | $(Limit-LoaderText $_ ($ld.Cols - 10))"
        }
        $ld.Failed = $true
        return $false
    }
    $ld.Done++
    if ($ld.Anim -and $ld.Idx -lt $ld.Total) {
        Write-LoaderLive '^_^' 'Step done' $c.G '' (Get-LoaderFullBar $ld.Done) "$($ld.Done) of $($ld.Total) done" $c.D
    }
    return $true
}

# Start-Process joins -ArgumentList with spaces and does not quote them, so quote each argument that
# needs it. (Windows quoting: wrap in double quotes, escape embedded double quotes.)
function ConvertTo-LoaderArgString([string[]]$Arguments) {
    return (($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' ')
}

function Invoke-LoaderStep {
    [CmdletBinding(DefaultParameterSetName = 'Cmd')]
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory, ParameterSetName = 'Cmd')][string]$Command,
        [Parameter(Mandatory, ParameterSetName = 'Exe')][string]$FilePath,
        [Parameter(ParameterSetName = 'Exe')][string[]]$ArgumentList = @()
    )
    $ld = $script:LD; $c = $script:LDC
    if ($ld.Failed) { return $false }
    $ld.Idx++
    $log = Join-Path $ld.Dir "step$($ld.Idx).log"
    $err = Join-Path $ld.Dir "step$($ld.Idx).err"
    $t0 = Get-Date

    if ($PSCmdlet.ParameterSetName -eq 'Cmd') {
        # -EncodedCommand (base64 UTF-16) passes the command intact, quotes and all. The prefix turns
        # off ANSI colour in the child's output so the log stays readable.
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(
                     "if (`$PSStyle) { `$PSStyle.OutputRendering = 'PlainText' }; $Command"))
        $FilePath = $script:LDPwsh
        $argString = ConvertTo-LoaderArgString @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded)
    } else {
        $argString = ConvertTo-LoaderArgString $ArgumentList
    }

    $proc = $null; $rc = 1; $finished = $false
    $pos = 0; $dir = 1; $tick = 0; $spin = @('|', '/', '-', '\')
    try {
        try {
            $proc = Start-Process -FilePath $FilePath -ArgumentList $argString -PassThru -NoNewWindow `
                        -RedirectStandardOutput $log -RedirectStandardError $err -WhatIf:$false
            $null = $proc.Handle   # Windows PowerShell 5.1 loses ExitCode unless the handle is cached
        } catch {
            Set-Content -LiteralPath $err -Value "cannot start $($FilePath): $($_.Exception.Message)" -WhatIf:$false
        }
        if ($proc) {
            if ($ld.Anim) { [Console]::Write("$($ld.Esc)[?25l") }   # hide the cursor while animating
            while (-not $proc.HasExited) {
                if ($ld.Anim) {
                    Clear-LoaderLive
                    Write-LoaderLive 'o_o' $ld.Verb "$($c.C)$($c.B)" $Label (Get-LoaderBounceBar $pos) `
                        "step $($ld.Idx) of $($ld.Total)  $($spin[$tick % 4])  working..." $c.D
                    $pos += $dir
                    if ($pos -ge ($ld.BarW - 4)) { $dir = -1 }
                    if ($pos -le 0) { $dir = 1 }
                    $tick++
                }
                Start-Sleep -Milliseconds 120
            }
            $proc.WaitForExit()
            $rc = $proc.ExitCode
        }
        $finished = $true
    } finally {
        if ($ld.Anim) { [Console]::Write("$($ld.Esc)[?25h") }        # always give the cursor back
        if (-not $finished) {                                        # Ctrl-C: stop the child, tidy up
            if ($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch { } }
            Clear-LoaderLive
            Write-Host "   $($c.R)Interrupted$($c.N)  stopped before finishing."
            Remove-LoaderDir
        }
    }

    Clear-LoaderLive
    $text = ''
    foreach ($f in @($log, $err)) {
        if (Test-Path -LiteralPath $f) { $text += (Get-Content -LiteralPath $f -Raw) + "`n" }
    }
    return (Complete-LoaderStep $Label $rc ((Get-Date) - $t0).TotalSeconds $text)
}

function Invoke-LoaderBlock {
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][scriptblock]$ScriptBlock)
    $ld = $script:LD
    if ($ld.Failed) { return $false }
    $ld.Idx++
    $t0 = Get-Date
    $script:LoaderSkip = $false
    $rc = 0
    Clear-LoaderLive
    try {
        # *>&1 folds every stream (Write-Host and Write-Warning included) into the text we keep.
        $text = (& $ScriptBlock *>&1 | Out-String)
    } catch {
        $rc = 1
        $text = $_.Exception.Message
    }
    if ($rc -eq 0 -and $script:LoaderSkip) { $rc = 10 }
    return (Complete-LoaderStep $Label $rc ((Get-Date) - $t0).TotalSeconds $text)
}

function Complete-Loader {
    $ld = $script:LD; $c = $script:LDC
    Clear-LoaderLive
    $secs = [int]((Get-Date) - $ld.Start).TotalSeconds
    Write-Host ''
    if (-not $ld.Failed) {
        $msg = "$($ld.Done) of $($ld.Total) done in ${secs}s"
        if ($ld.Skipped -gt 0) { $msg += " ($($ld.Skipped) skipped)" }
        Write-LoaderLive '^_^' 'All done' "$($c.G)$($c.B)" '' (Get-LoaderFullBar $ld.Done) $msg $c.G
        Write-Host "   $($c.G)$($c.B)SUCCESS$($c.N)"
        Remove-LoaderDir
        return $true
    }
    Write-LoaderLive 'x_x' 'Stopped' "$($c.R)$($c.B)" '' (Get-LoaderFullBar $ld.Done) `
        "$($ld.Done) of $($ld.Total) done, step $($ld.Idx) failed" $c.R
    Write-Host "   $($c.R)$($c.B)FAILED$($c.N)  fix the step above and run again."
    Write-Host "   $($c.D)logs kept in $($ld.Dir)$($c.N)"
    return $false
}
