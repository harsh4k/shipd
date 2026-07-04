# Live full-screen TUI (eDEX-style, green-on-black). Pure ANSI/$PSStyle, no deps.
# Reuses Get-SystemStats/Get-FocusedProcessName/Get-IdleSeconds (activity.ps1),
# Find-Repos/Get-DayCommits (git_scan.ps1), Get-Bar (report.ps1).

$script:TH = @{
    G = $PSStyle.Foreground.FromRgb(0, 200, 100)    # text
    B = $PSStyle.Foreground.FromRgb(185, 255, 205)  # bright accent
    D = $PSStyle.Foreground.FromRgb(0, 110, 60)     # dim / borders
    R = $PSStyle.Reset
}

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
    $chars = (Get-Date).ToString('HH:mm:ss').ToCharArray()
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
    $lines = @()
    foreach ($root in $Config.git_roots) {
        foreach ($repo in Find-Repos -Root $root) {
            $commits = @(Get-DayCommits -Repo $repo)
            if (-not $commits.Count) { continue }
            $net = ($commits | Measure-Object NetLines -Sum).Sum
            $sign = if ($net -ge 0) { '+' } else { '' }
            $lines += "$($TH.B)$(Split-Path $repo -Leaf)$($TH.D)  $($commits.Count)c $sign$net"
            foreach ($c in $commits | Select-Object -First 5) {
                $msg = $c.Message; if ($msg.Length -gt 20) { $msg = $msg.Substring(0, 19) + '…' }
                $lines += "$($TH.D) $($c.Hash)$($TH.G) $msg"
            }
        }
    }
    if (-not $lines.Count) { $lines = @("$($TH.D)no commits today") }
    $lines
}

function Get-TodaySnapSummary {
    param($Config, [string]$LogPath)
    if (-not (Test-Path $LogPath)) { return $null }
    $snaps = @(Get-Content $LogPath | ForEach-Object { ConvertFrom-Json $_ } |
        Where-Object { ([datetime]$_.timestamp).Date -eq (Get-Date).Date })
    if (-not $snaps.Count) { return $null }
    [pscustomobject]@{
        Count = $snaps.Count
        Idle  = @($snaps | Where-Object { $_.idle_seconds -ge $Config.idle_threshold_seconds }).Count
        Focus = @($snaps | Group-Object focused | Sort-Object Count -Descending)
        Games = @($snaps | ForEach-Object { $_.games_running } | Sort-Object -Unique)
    }
}

function Build-DashFrame {
    param($Config, [string[]]$GitLines, $Snap, $Stats, [double[]]$CpuHist, [int]$W, [int]$H, $Mem, [string]$MemMsg = '')
    $ph = $H - 2
    $lw = 34; $rw = 32; $mw = $W - $lw - $rw

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
    $left += "CPU $(Get-Bar $Stats.cpu 14) $($TH.B)$($Stats.cpu)%"
    $left += "$($TH.D)    $(Get-Sparkline $CpuHist ($liw - 5))"
    $left += "RAM $(Get-Bar $ramPct 14) $($TH.B)$($Stats.ram_used)/$($Stats.ram_total)"
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
    $fmt = "{0,7} {1,-$nameW} {2,10:N1} {3,10:N0}"
    $mid = @("$($TH.D)" + ("{0,7} {1,-$nameW} {2,10} {3,10}" -f 'PID', 'NAME', 'CPU(s)', 'MEM(MB)'))
    Get-Process | Sort-Object CPU -Descending | Select-Object -First ($ph - 3) | ForEach-Object {
        $n = $_.ProcessName
        if ($n.Length -gt $nameW) { $n = $n.Substring(0, $nameW - 1) + '…' }
        $mid += ($fmt -f $_.Id, $n, $_.CPU, ($_.WorkingSet64 / 1MB))
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
    $frame + "$($TH.D)  q quit · g rescan git · f free ram$($TH.R)"
}

function Show-LiveDashboard {
    param($Config, [string]$LogPath)
    $W = $Host.UI.RawUI.WindowSize.Width; $H = $Host.UI.RawUI.WindowSize.Height
    if ($W -lt 110 -or $H -lt 24) {
        Write-Host "shipd dashboard needs a window of at least 110x24 (yours is ${W}x${H}) — maximize the terminal and retry"
        return
    }
    $gitLines = Get-GitPanelLines $Config
    $summary = Get-TodaySnapSummary $Config $LogPath
    $cpuHist = @()
    $tick = 0
    $memMsg = ''; $memMsgTicks = 0
    [Console]::CursorVisible = $false
    Clear-Host
    try {
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
            if ($tick -gt 0 -and $tick % 15 -eq 0) { $summary = Get-TodaySnapSummary $Config $LogPath }
            $snap = [pscustomobject]@{ Focused = Get-FocusedProcessName; IdleSec = Get-IdleSeconds; Summary = $summary }
            $frame = Build-DashFrame -Config $Config -GitLines $gitLines -Snap $snap -Stats $stats -CpuHist $cpuHist -W $W -H $H -Mem $mem -MemMsg $memMsg
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
                            Start-Process pwsh -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile', '-File', "$PSScriptRoot\shipd.ps1", 'free'
                            $freed = [math]::Round([math]::Max(0, $mem.standby - (Get-MemoryBreakdown).standby), 2)
                            $memMsg = "✓ freed $freed GB"
                        }
                        catch { $memMsg = 'free ram cancelled' }   # UAC declined — not an error
                        $memMsgTicks = 5
                    }
                }
            }
        }
    }
    finally {
        [Console]::CursorVisible = $true
        Write-Host $PSStyle.Reset -NoNewline
        Clear-Host
    }
}
