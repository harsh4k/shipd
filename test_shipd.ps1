# Minimal self-checks: numstat parser + repo-scan pruning.
$ErrorActionPreference = 'Stop'
. (Get-Item -LiteralPath (Join-Path $PSScriptRoot 'git_scan.ps1'))

# --- numstat parser ---
$lines = @(
    'COMMIT|abc1234|fix: the thing',
    '10	3	foo.py',
    '-	-	img.png',
    '',
    'COMMIT|def5678|msg|with|pipes',
    '0	5	bar.py'
)
$c = @(ConvertFrom-NumstatLog -Lines $lines)
if ($c.Count -ne 2) { throw "expected 2 commits, got $($c.Count)" }
if ($c[0].Files -ne 2 -or $c[0].NetLines -ne 7) { throw "commit1 parse wrong: $($c[0].Files) files, $($c[0].NetLines) lines" }
if ($c[1].Message -ne 'msg|with|pipes') { throw "pipes in message not preserved: $($c[1].Message)" }
if ($c[1].NetLines -ne -5) { throw "net lines wrong: $($c[1].NetLines)" }

# --- Find-Repos: depth cap + node_modules prune ---
$tmp = Join-Path ([IO.Path]::GetTempPath()) "shipd_test_$(Get-Random)"
foreach ($d in 'repo1\.git', 'node_modules\repo2\.git', 'a\b\c\d\repo3\.git') {
    New-Item -ItemType Directory -Force (Join-Path $tmp $d) | Out-Null
}
$found = @(Find-Repos -Root $tmp)
Remove-Item -Recurse -Force $tmp
if ($found.Count -ne 1 -or $found[0] -notlike '*repo1') {
    throw "expected only repo1 (node_modules pruned, repo3 beyond depth), got: $($found -join '; ')"
}

# --- dashboard frame geometry: every line exactly W wide, ph+1 lines ---
. (Get-Item -LiteralPath (Join-Path $PSScriptRoot 'report.ps1'))
. (Get-Item -LiteralPath (Join-Path $PSScriptRoot 'dashboard.ps1'))
$stats = [pscustomobject]@{ cpu = 42; gpu = '10% 60C'; ram_used = 8.5; ram_total = 16; disks = @('C: 1/2 GB', 'X: 3/4 GB') }
$snap = [pscustomobject]@{ Focused = 'Code'; IdleSec = 1.5; Summary = $null }
$palette = Get-ShipdPalette
$sample = @{ At = 12; Processes = @(
    [pscustomobject]@{ Id = 1; Name = 'unreadable'; CpuSeconds = $null; MemoryMB = 1 }
    [pscustomobject]@{ Id = 2; Name = 'idle'; CpuSeconds = 0; MemoryMB = 2 }
    [pscustomobject]@{ Id = 3; Name = 'busy'; CpuSeconds = 4; MemoryMB = 3 }
    [pscustomobject]@{ Id = 4; Name = ('longprocessname' * 8); CpuSeconds = 2; MemoryMB = 4 }
) }
$previous = @{ At = 10; Processes = @(
    [pscustomobject]@{ Id = 1; CpuSeconds = 1 }
    [pscustomobject]@{ Id = 2; CpuSeconds = 0 }
    [pscustomobject]@{ Id = 3; CpuSeconds = 0 }
) }
foreach ($dim in @(@(110, 24), @(120, 30), @(140, 30), @(160, 45), @(180, 45), @(240, 45))) {
    $W = $dim[0]; $H = $dim[1]
    $mem = [pscustomobject]@{ total = 16; in_use = 9.25; standby = 4.5; modified = 0.25; free = 2 }
    $frameArgs = @{ GitLines = @('plain', "$($palette.B)colored line"); Snap = $snap; Stats = $stats
        CpuHist = @(0, 30, 100); W = $W; H = $H; Mem = $mem; MemMsg = 'freed 2.5 GB'; ProcessSample = $sample }
    $frame = @(Build-DashFrame @frameArgs -PreviousSample $previous)
    if ($frame.Count -ne $H - 1) { throw "frame ${W}x${H}: expected $($H - 1) lines, got $($frame.Count)" }
    $bad = $frame | Where-Object { (Get-VisLen $_) -ne $W }
    if ($bad) { throw "frame ${W}x${H}: ragged lines (visible width != $W):`n$($bad -join "`n")" }
    if ($frame[1] -notmatch 'CPU%' -or $frame[1] -match 'CPU\(s\)') { throw 'process CPU header incorrect' }
    if ($frame[2] -notmatch 'busy' -or $frame[3] -notmatch 'idle' -or $frame[4] -notmatch 'unreadable') {
        throw 'processes must sort by live CPU, zero before unavailable'
    }
    $expected = '{0:N1}' -f (Get-ProcessCpuPercent 4 0 2)
    if ($frame[2] -notmatch [regex]::Escape($expected)) { throw 'process CPU not formatted to one decimal' }
    $first = @(Build-DashFrame @frameArgs)
    if (($first[4] -replace "`e\[[0-9;]*m", '') -notmatch 'busy\s+-\s+3') { throw 'first sample must show - for readable CPU times too' }
}

# --- CPU deltas: total machine capacity, missing readings, elapsed time, counters going backwards ---
foreach ($case in @(
    @{ Current = 4; Prior = 2; Wall = 2; Cores = 4; Want = 25 }
    @{ Current = 2.01; Prior = 2; Wall = 2; Cores = 2; Want = 0.25 }
    @{ Current = 2; Prior = 2; Wall = 2; Cores = 4; Want = 0 }
    @{ Current = 20; Prior = 0; Wall = 2; Cores = 4; Want = 100 }
    @{ Current = 4; Prior = $null; Wall = 2; Cores = 4; Want = $null }
    @{ Current = $null; Prior = 2; Wall = 2; Cores = 4; Want = $null }
    @{ Current = 4; Prior = 2; Wall = 0; Cores = 4; Want = $null }
    @{ Current = 4; Prior = 2; Wall = -1; Cores = 4; Want = $null }
    @{ Current = 4; Prior = 2; Wall = 2; Cores = 0; Want = $null }
    @{ Current = 1; Prior = 2; Wall = 2; Cores = 4; Want = $null }
)) {
    $actual = Get-ProcessCpuPercent $case.Current $case.Prior $case.Wall $case.Cores
    if ($null -eq $case.Want) {
        if ($null -ne $actual) { throw "CPU delta should be unavailable: $actual" }
    }
    elseif ([math]::Abs($actual - $case.Want) -gt 0.000001) { throw "CPU delta: expected $($case.Want), got $actual" }
}
$denied = [pscustomobject]@{ Id = 99; ProcessName = 'denied'; WorkingSet64 = 1MB }
$denied | Add-Member -MemberType ScriptProperty -Name TotalProcessorTime -Value { throw 'access denied' }
$readable = [pscustomobject]@{ Id = 98; ProcessName = 'readable'; WorkingSet64 = 2MB; TotalProcessorTime = [timespan]::FromSeconds(4) }
$captured = Get-ProcessCpuSample -Processes @($denied, $readable)
if ($null -ne $captured.Processes[0].CpuSeconds -or $captured.Processes[1].CpuSeconds -ne 4) {
    throw 'process sampling must tolerate access denied and preserve readable CPU times'
}

# --- shared thresholds, NO_COLOR, and OutputRendering restoration ---
$savedColor = $env:NO_COLOR; $savedRendering = $PSStyle.OutputRendering
try {
    $env:NO_COLOR = ''
    $colors = Get-ShipdPalette
    foreach ($case in @(@(59, 'Cpu', 'G'), @(60, 'Cpu', 'Warn'), @(89, 'Cpu', 'Warn'),
            @(90, 'Cpu', 'Crit'), @(69, 'Ram', 'G'), @(70, 'Ram', 'Warn'), @(90, 'Ram', 'Crit'))) {
        if ((Get-UsageColor $case[0] $case[1]) -ne $colors[$case[2]]) { throw 'shared color thresholds incorrect' }
    }
    if (-not $colors.G) { throw 'empty NO_COLOR must allow colors' }
    $data = [pscustomobject]@{ Day = '2026-07-01'; Stats = $stats; Repos = @(); Act = $null }
    if ((Format-ReportText $data) -match "`e\[") { throw 'saved report contains ANSI with colors enabled' }
    foreach ($value in '1', '0') {
        $env:NO_COLOR = $value
        if (@((Get-ShipdPalette).Values | Where-Object { $_ -ne '' }).Count) { throw 'NO_COLOR palette not empty' }
        foreach ($width in 110..240) {
            $frameArgs.W = $width
            $plain = @(Build-DashFrame @frameArgs -PreviousSample $previous)
            if ($plain -match "`e\[") { throw 'NO_COLOR frame contains ANSI' }
            if (@($plain | Where-Object Length -ne $width).Count) { throw "NO_COLOR frame width != $width" }
        }
        $PSStyle.OutputRendering = 'ANSI'
        $report = Show-Dashboard $data 6>&1 | Out-String
        if ($report -match "`e\[" -or $PSStyle.OutputRendering -ne 'ANSI') { throw 'NO_COLOR report or rendering restoration failed' }
        if ((Format-ReportText $data) -match "`e\[") { throw 'saved report contains ANSI' }
    }
    # A rendering failure must restore the caller's setting too.
    $renderFailed = $false
    try { Show-Dashboard ([pscustomobject]@{ Stats = @{ ram_used = 1; ram_total = 0 } }) 6>$null }
    catch { $renderFailed = $true }
    if (-not $renderFailed -or $PSStyle.OutputRendering -ne 'ANSI') { throw 'report failure restoration check failed' }
}
finally { $env:NO_COLOR = $savedColor; $PSStyle.OutputRendering = $savedRendering }

# --- snapshot log: torn line skipped, next append starts a fresh line, other days filtered out ---
$log = Join-Path ([IO.Path]::GetTempPath()) "shipd_snaps_$(Get-Random).jsonl"
@(
    '{"timestamp":"2026-07-01T10:00:00","focused":"Code","idle_seconds":1,"games_running":[]}'
    '{"timestamp":"2026-07-02T10:00:00","focused":"Code","idle_seconds":1,"games_running":[]}'
    '{"timestamp":"2026-07-01T10:10:00","focused":"pwsh","idle_seconds":900,"games_running":["steam"]}'
) | Set-Content -LiteralPath $log
[IO.File]::AppendAllText($log, '{"timestamp":"2026-07-01T10:20:00","focu')   # torn: no trailing newline
Add-SnapshotLine -LogPath $log -Snapshot ([pscustomobject]@{ timestamp = '2026-07-01T10:30:00'; focused = 'Code'; idle_seconds = 2; games_running = @() })
$sum = Get-DaySnapSummary -Config ([pscustomobject]@{ idle_threshold_seconds = 300 }) -LogPath $log -Date ([datetime]'2026-07-01')
Remove-Item -LiteralPath $log
if ($sum.Count -ne 3) { throw "snap summary: expected 3 snapshots on 2026-07-01 (torn one skipped, appended one kept), got $($sum.Count)" }
if ($sum.Idle -ne 1) { throw "snap summary: expected 1 idle, got $($sum.Idle)" }
if ("$($sum.Games)" -ne 'steam') { throw "snap summary: games wrong: $($sum.Games)" }

# --- GPU: per-process instances summed per engine, busiest engine wins, capped at 100 ---
. (Get-Item -LiteralPath (Join-Path $PSScriptRoot 'activity.ps1'))
$s = { param($i, $v) [pscustomobject]@{ InstanceName = $i; CookedValue = $v } }
$gpuSamples = @(
    (& $s 'pid_10_luid_0x0_0x1_phys_0_eng_0_engtype_3d' 30), (& $s 'pid_11_luid_0x0_0x1_phys_0_eng_0_engtype_3d' 25)
    (& $s 'pid_12_luid_0x0_0x1_phys_0_eng_1_engtype_3d' 40)
)
if ((Get-GpuUtilization $gpuSamples) -ne 55) { throw "gpu: expected 55 (30+25 on eng_0), got $(Get-GpuUtilization $gpuSamples)" }
if ((Get-GpuUtilization @((& $s 'pid_1_e' 80), (& $s 'pid_2_e' 70))) -ne 100) { throw 'gpu: expected cap at 100' }

# --- day commits: mine only (any case), every branch + detached HEAD, orphan-safe, worktrees once ---
$root = Join-Path ([IO.Path]::GetTempPath()) "shipd_git_$(Get-Random)"
$repo = Join-Path $root 'zapp'          # main checkout sorts AFTER its worktree on purpose
$wt = Join-Path $root 'a-wt'
New-Item -ItemType Directory -Force $repo | Out-Null
$day = [datetime]'2026-07-01'
$savedEnv = @{}
foreach ($v in 'GIT_AUTHOR_DATE', 'GIT_COMMITTER_DATE', 'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM') { $savedEnv[$v] = [Environment]::GetEnvironmentVariable($v) }
$emptyCfg = Join-Path $root 'empty.gitconfig'
# fixed day (no midnight flake) and no global/system config (a dev's signing, hooks or email can't leak in)
$env:GIT_AUTHOR_DATE = $env:GIT_COMMITTER_DATE = '2026-07-01T12:00:00'
$env:GIT_CONFIG_NOSYSTEM = '1'
function Invoke-TestGit {
    param([string]$Dir)
    $o = git -C $Dir @args 2>&1
    if ($LASTEXITCODE) { throw "git $($args -join ' ') failed: $o" }
}
try {
    New-Item -ItemType File -Force -Path $emptyCfg | Out-Null
    $env:GIT_CONFIG_GLOBAL = $emptyCfg
    Invoke-TestGit $repo init -q -b main
    Invoke-TestGit $repo config user.email 'me@example.com'
    Invoke-TestGit $repo config user.name 'me'
    Invoke-TestGit $repo commit -q --allow-empty -m 'mine on main'
    Invoke-TestGit $repo -c user.email=Me@Example.COM commit -q --allow-empty -m 'mine, other case'
    Invoke-TestGit $repo -c user.email=other@example.com -c user.name=other commit -q --allow-empty -m 'someone else'
    Invoke-TestGit $repo checkout -q -b feature
    Invoke-TestGit $repo commit -q --allow-empty -m 'mine on feature'
    Invoke-TestGit $repo worktree add -q --detach $wt main
    Invoke-TestGit $wt commit -q --allow-empty -m 'mine detached'
    Invoke-TestGit $repo checkout -q --orphan fresh   # unborn HEAD must not hide the other branches
    $msgs = @(Get-DayCommits -Repo $repo -Date $day | ForEach-Object Message)
    $msgsWt = @(Get-DayCommits -Repo $wt -Date $day | ForEach-Object Message)
    $msgsOverride = @(Get-DayCommits -Repo $repo -Date $day -AuthorEmails @('other@example.com') | ForEach-Object Message)
    $repos = @(Get-DayRepoCommits -Config ([pscustomobject]@{ git_roots = @($root) }) -Date $day)
    Invoke-TestGit $wt config --unset user.email   # no identity anywhere: HEAD only, every author
    $msgsNoEmail = @(Get-DayCommits -Repo $wt -Date $day | ForEach-Object Message)
}
finally {
    foreach ($v in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($v, $savedEnv[$v]) }
    Remove-Item -LiteralPath $root -Recurse -Force
}
if (($msgs | Sort-Object) -join '; ' -ne 'mine on feature; mine on main; mine, other case') {
    throw "day commits: expected only my commits from all branches, got: $($msgs -join '; ')"
}
if ($msgsWt -notcontains 'mine detached') { throw "day commits: detached HEAD commit missing, got: $($msgsWt -join '; ')" }
if ("$msgsOverride" -ne 'someone else') { throw "day commits: author_emails override ignored, got: $($msgsOverride -join '; ')" }
if (($msgsNoEmail | Sort-Object) -join '; ' -ne 'mine detached; mine on main; mine, other case; someone else') {
    throw "day commits: no-email fallback should be HEAD only, every author; got: $($msgsNoEmail -join '; ')"
}
$main = $repos | Where-Object Name -eq 'zapp'
$total = ($repos | ForEach-Object { $_.Commits.Count } | Measure-Object -Sum).Sum
if ($total -ne 4 -or $main.Commits.Count -ne 3) {
    throw "day repo commits: expected 4 commits, 3 credited to the main checkout; got $total total, $($main.Commits.Count) on zapp"
}

# --- UAC cancel (ERROR_CANCELLED, possibly wrapped) vs a real failure ---
. (Get-Item -LiteralPath (Join-Path $PSScriptRoot 'memory.ps1'))
$cancel = [InvalidOperationException]::new('wrapped', [ComponentModel.Win32Exception]::new(1223))
if (-not (Test-UacCancelled $cancel)) { throw 'uac: wrapped ERROR_CANCELLED not detected' }
if (Test-UacCancelled ([ComponentModel.Win32Exception]::new(2))) { throw 'uac: file-not-found treated as a cancel' }

# --- memory breakdown sanity ---
$m = Get-MemoryBreakdown
if ($null -ne $m) {
    foreach ($p in 'total', 'in_use', 'standby', 'modified', 'free') {
        if ($m.$p -lt 0) { throw "memory: negative $p ($($m.$p))" }
    }
    $sum = $m.in_use + $m.standby + $m.modified + $m.free
    if ([math]::Abs($sum - $m.total) -gt $m.total * 0.1) {
        throw "memory: parts sum $sum GB but total is $($m.total) GB"
    }
}

Write-Output 'all checks passed'
