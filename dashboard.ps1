# Live full-screen TUI (eDEX-style, green-on-black). Pure ANSI/$PSStyle, no deps.
# Reuses Get-SystemStats/Get-FocusedProcessName/Get-IdleSeconds (activity.ps1),
# Find-Repos/Get-DayCommits (git_scan.ps1), Get-Bar (report.ps1).

$script:DigitFont = @{
    '0' = '███', '█ █', '█ █', '█ █', '███'
    '1' = ' █ ', '██ ', ' █ ', ' █ ', '███'
    '2' = '███', '  █', '███', '█  ', '███'
    '3' = '███', '  █', '███', '  █', '███'
    '4' = '█ █', '█ █', '███', '  █', '  █'
    '5' = '███', '█  ', '███', '  █', '███'
    '6' = '███', '█  ', '███', '█ █', '███'
    '7' = '███', '  █', '  █', '  █', '  █'
    '8' = '███', '█ █', '███', '█ █', '███'
    '9' = '███', '█ █', '███', '  █', '███'
    ':' = ' ', '█', ' ', '█', ' '
}

function Get-BigClock {
    $chars = (Get-Date).ToString('HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture).ToCharArray()
    foreach ($r in 0..4) {
        -join ($chars | ForEach-Object { $script:DigitFont["$_"][$r] + ' ' })
    }
}

function Get-Sparkline {
    param([double[]]$Values, [int]$Width)
    $bars = '▁▂▃▄▅▆▇█'
    $v = @($Values | Select-Object -Last $Width)
    $s = -join ($v | ForEach-Object { $bars[[math]::Max(0, [math]::Min(7, [math]::Floor($_ / 12.6)))] })
    $s.PadLeft($Width)
}

function Get-VisLen([string]$s) { ($s -replace "`e\[[0-9;]*m", '').Length }

function New-Panel {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'builds strings; changes no system state')]
    param([string]$Title, [string[]]$Body, [int]$Width, [int]$Height)
    $iw = $Width - 2
    $out = @("$($TH.D)┌─ $($TH.B)$Title$($TH.D) $('─' * [math]::Max(0, $iw - $Title.Length - 3))┐$($TH.R)")
    for ($i = 0; $i -lt $Height - 2; $i++) {
        $line = if ($i -lt $Body.Count) { [string]$Body[$i] } else { '' }
        $pad = $iw - (Get-VisLen $line)
        if ($pad -lt 0) {
            # overflow: drop colors so we can clip safely (geometry beats styling)
            $line = ($line -replace "`e\[[0-9;]*m", '').Substring(0, $iw)
            $pad = 0
        }
        $out += "$($TH.D)│$($TH.G)$line$(' ' * $pad)$($TH.D)│$($TH.R)"
    }
    $out + "$($TH.D)└$('─' * $iw)┘$($TH.R)"
}

function Get-GitPanelLines {
    param($Config)
    $TH = Get-ShipdPalette
    $lines = @()
    foreach ($repo in Get-DayRepoCommits -Config $Config) {
        $sign = if ($repo.NetLines -ge 0) { '+' } else { '' }
        $lines += "$($TH.B)$($repo.Name)$($TH.D)  $($repo.Commits.Count)c $sign$($repo.NetLines)"
        foreach ($c in $repo.Commits | Select-Object -First 5) {
            $msg = $c.Message; if ($msg.Length -gt 20) { $msg = $msg.Substring(0, 19) + '…' }
            $lines += "$($TH.D) $($c.Hash)$($TH.G) $msg"
        }
    }
    if (-not $lines.Count) { $lines = @("$($TH.D)no commits today") }
    $lines
}

function Get-ProcessCpuPercent {
    param([Nullable[double]]$CpuSeconds, [Nullable[double]]$PreviousCpuSeconds,
        [double]$ElapsedSeconds, [int]$ProcessorCount = [Environment]::ProcessorCount)
    if ($null -eq $CpuSeconds -or $null -eq $PreviousCpuSeconds -or
        $ElapsedSeconds -le 0 -or $ProcessorCount -le 0 -or $CpuSeconds -lt $PreviousCpuSeconds) { return $null }
    [math]::Min(100.0, ($CpuSeconds - $PreviousCpuSeconds) / ($ElapsedSeconds * $ProcessorCount) * 100)
}

function Get-ProcessCpuSample {
    param($Processes = (Get-Process))
    $at = [Diagnostics.Stopwatch]::GetTimestamp() / [double][Diagnostics.Stopwatch]::Frequency
    $rows = @(foreach ($process in $Processes) {
        $cpu = $null; $memory = $null
        try { $cpu = $process.TotalProcessorTime.TotalSeconds }
        catch { Write-Verbose "CPU time unavailable for PID $($process.Id): $_" }
        try { $memory = $process.WorkingSet64 / 1MB }
        catch { Write-Verbose "Memory unavailable for PID $($process.Id): $_" }
        [pscustomobject]@{ Id = $process.Id; Name = $process.ProcessName; CpuSeconds = $cpu; MemoryMB = $memory }
    })
    @{ At = $at; Processes = $rows }
}

function Build-DashFrame {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'preserves the existing frame builder name and callers')]
    param([string[]]$GitLines, $Snap, $Stats, [double[]]$CpuHist, [int]$W, [int]$H, $Mem, [string]$MemMsg = '',
        $ProcessSample = (Get-ProcessCpuSample), $PreviousSample)
    $TH = Get-ShipdPalette
    $ph = $H - 2
    $lw = [int][math]::Clamp([math]::Floor($W * 0.3), 34, 64)
    $rw = [int][math]::Clamp([math]::Floor($W * 0.3), 32, 64)
    $mw = $W - $lw - $rw

    # ── left: clock + system ──
    $liw = $lw - 2
    $left = @()
    foreach ($row in Get-BigClock) {
        $left += "$($TH.B)$(' ' * [math]::Max(0, [math]::Floor(($liw - $row.Length) / 2)))$row"
    }
    $d = (Get-Date).ToString('ddd dd MMM yyyy')
    $left += "$($TH.D)$(' ' * [math]::Max(0, [math]::Floor(($liw - $d.Length) / 2)))$d"
    $left += ''
    $ramPct = $Stats.ram_used / $Stats.ram_total * 100
    $left += "CPU $(Get-UsageColor $Stats.cpu Cpu $TH)$(Get-Bar $Stats.cpu 14) $($Stats.cpu)%$($TH.G)"
    $left += "$($TH.D)    $(Get-Sparkline $CpuHist ($liw - 5))"
    $left += "RAM $(Get-UsageColor $ramPct Ram $TH)$(Get-Bar $ramPct 14) $($Stats.ram_used)/$($Stats.ram_total)$($TH.G)"
    $left += "GPU $($TH.B)$($Stats.gpu)"
    $up = [TimeSpan]::FromMilliseconds([Environment]::TickCount64)
    $left += "UP  $($TH.B)$($up.Days)d $($up.Hours)h $($up.Minutes)m"
    $left += ''
    foreach ($disk in $Stats.disks) { $left += "$($TH.D)$disk" }
    if ($Mem) {
        $left += ''
        $left += "$($TH.D)MEMORY$(if ($MemMsg) { "  $($TH.B)$MemMsg" })"
        foreach ($row in @(@('use', $Mem.in_use), @('stby', $Mem.standby), @('mod', $Mem.modified), @('free', $Mem.free))) {
            $left += ('{0,-5}' -f $row[0]) + (Get-Bar ($row[1] / $Mem.total * 100) 12) + " $($TH.B)$($row[1])"
        }
    }

    # ── middle: processes ──
    $miw = $mw - 2
    $nameW = $miw - 30
    $fmt = "{0,7} {1,-$nameW} {2,10} {3,10}"
    $mid = @("$($TH.D)" + ($fmt -f 'PID', 'NAME', 'CPU%', 'MEM(MB)'))
    $previous = @{}
    if ($PreviousSample) { foreach ($row in $PreviousSample.Processes) { $previous[$row.Id] = $row.CpuSeconds } }
    $elapsed = if ($PreviousSample) { $ProcessSample.At - $PreviousSample.At } else { 0 }
    $rows = foreach ($row in $ProcessSample.Processes) {
        $pct = Get-ProcessCpuPercent $row.CpuSeconds $previous[$row.Id] $elapsed
        [pscustomobject]@{ Id = $row.Id; Name = $row.Name; Cpu = $pct; MemoryMB = $row.MemoryMB }
    }
    $rows | Sort-Object -Stable @{ Expression = { $null -ne $_.Cpu }; Descending = $true },
        @{ Expression = { $_.Cpu }; Descending = $true } | Select-Object -First ($ph - 3) | ForEach-Object {
        $n = $_.Name
        if ($n.Length -gt $nameW) { $n = $n.Substring(0, $nameW - 1) + '…' }
        $cpuText = if ($null -eq $_.Cpu) { '-' } else { '{0:N1}' -f $_.Cpu }
        $memText = if ($null -eq $_.MemoryMB) { '-' } else { '{0:N0}' -f $_.MemoryMB }
        $mid += ($fmt -f $_.Id, $n, $cpuText, $memText)
    }

    # ── right: activity + git ──
    $ah = [math]::Min(13, [math]::Floor($ph / 2))
    $act = @()
    $act += "focused    $($TH.B)$($Snap.Focused)"
    $act += "idle       $($TH.B)$($Snap.IdleSec)s"
    $act += ''
    $s = $Snap.Summary
    if ($s) {
        $act += "snapshots  $($TH.B)$($s.Count)"
        $act += "$($TH.D)           $($s.Count - $s.Idle) active · $($s.Idle) idle"
        $act += ''
        $max = ($s.Focus | Measure-Object Count -Maximum).Maximum
        foreach ($g in $s.Focus | Select-Object -First 4) {
            $name = if ($g.Name) { "$($g.Name)" } else { '?' }
            if ($name.Length -gt 12) { $name = $name.Substring(0, 12) }
            $act += ('{0,-13}' -f $name) + $TH.B + (Get-Bar ($g.Count / $max * 100) 10) + " $($g.Count)"
        }
        if ($s.Games.Count) { $act += "$($TH.B)games: $($s.Games -join ',')" }
    }
    else { $act += "$($TH.D)no snapshots yet" }
    $right = @(New-Panel 'ACTIVITY' $act $rw $ah) + @(New-Panel 'GIT TODAY' $GitLines $rw ($ph - $ah))

    $leftP = New-Panel 'SHIPD' $left $lw $ph
    $midP = New-Panel 'PROCESSES' $mid $mw $ph
    $frame = for ($i = 0; $i -lt $ph; $i++) { $leftP[$i] + $midP[$i] + $right[$i] }
    $frame += "$($TH.D)$('  q quit · g rescan git · f free ram'.PadRight($W))$($TH.R)"
    if ($env:NO_COLOR) { $frame -replace "`e\[[0-9;]*m", '' } else { $frame }
}

function Show-LiveDashboard {
    param($Config, [string]$LogPath)
    $W = $Host.UI.RawUI.WindowSize.Width; $H = $Host.UI.RawUI.WindowSize.Height
    if ($W -lt 110 -or $H -lt 24) {
        Write-Host "shipd dashboard needs a window of at least 110x24 (yours is ${W}x${H}) — maximize the terminal and retry"
        return
    }
    $TH = Get-ShipdPalette
    $rendering = $PSStyle.OutputRendering
    if ($env:NO_COLOR) { $PSStyle.OutputRendering = 'PlainText' }
    try {
        $gitLines = Get-GitPanelLines $Config
        $summary = Get-DaySnapSummary $Config $LogPath
        $cpuHist = @()
        $previousSample = $null
        $tick = 0
        $memMsg = ''; $memMsgTicks = 0
        [Console]::CursorVisible = $false
        Clear-Host
        while ($true) {
            $nW = $Host.UI.RawUI.WindowSize.Width; $nH = $Host.UI.RawUI.WindowSize.Height
            if ($nW -ne $W -or $nH -ne $H) {
                $W = $nW; $H = $nH; Clear-Host
                if ($W -lt 110 -or $H -lt 24) { return }
            }
            $stats = Get-SystemStats
            $mem = Get-MemoryBreakdown
            if ($memMsgTicks -gt 0) { $memMsgTicks-- } else { $memMsg = '' }
            $cpuHist = @($cpuHist + [double]$stats.cpu | Select-Object -Last 60)
            if ($tick -gt 0 -and $tick % 15 -eq 0) { $summary = Get-DaySnapSummary $Config $LogPath }
            $snap = [pscustomobject]@{ Focused = Get-FocusedProcessName; IdleSec = Get-IdleSeconds; Summary = $summary }
            $sample = Get-ProcessCpuSample
            $frameArgs = @{ GitLines = $gitLines; Snap = $snap; Stats = $stats; CpuHist = $cpuHist
                W = $W; H = $H; Mem = $mem; MemMsg = $memMsg; ProcessSample = $sample; PreviousSample = $previousSample }
            $frame = Build-DashFrame @frameArgs
            $previousSample = $sample
            [Console]::SetCursorPosition(0, 0)
            Write-Host ($frame -join "`n") -NoNewline
            $tick++
            foreach ($i in 1..10) {          # 2s tick, sliced so q reacts fast
                Start-Sleep -Milliseconds 200
                while ([Console]::KeyAvailable) {
                    $k = [Console]::ReadKey($true)
                    if ($k.KeyChar -in 'q', 'Q') { return }
                    if ($k.KeyChar -in 'g', 'G') { $gitLines = Get-GitPanelLines $Config }
                    if ($k.KeyChar -in 'f', 'F' -and $mem) {
                        try {
                            $freed = Invoke-ElevatedFree -ShipdScript (Join-Path $PSScriptRoot 'shipd.ps1') -Before $mem
                            $memMsg = if ($null -eq $freed) { 'free ram cancelled' } else { "✓ freed $freed GB" }
                        }
                        catch { $memMsg = 'free ram failed' }
                        $memMsgTicks = 5
                    }
                }
            }
        }
    }
    finally {
        $PSStyle.OutputRendering = $rendering
        [Console]::CursorVisible = $true
        Write-Host $TH.R -NoNewline
        Clear-Host
    }
}
