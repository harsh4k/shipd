# Minimal self-checks: numstat parser + repo-scan pruning.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\git_scan.ps1"

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
. "$PSScriptRoot\report.ps1"
. "$PSScriptRoot\dashboard.ps1"
$stats = [pscustomobject]@{ cpu = 42; gpu = '10% 60C'; ram_used = 8.5; ram_total = 16; disks = @('C: 1/2 GB', 'X: 3/4 GB') }
$snap = [pscustomobject]@{ Focused = 'Code'; IdleSec = 1.5; Summary = $null }
foreach ($dim in @(@(120, 30), @(110, 24), @(160, 45))) {
    $W = $dim[0]; $H = $dim[1]
    $mem = [pscustomobject]@{ total = 16; in_use = 9.25; standby = 4.5; modified = 0.25; free = 2 }
    $frame = @(Build-DashFrame -GitLines @('plain', "$($TH.B)colored line") -Snap $snap -Stats $stats -CpuHist @(0, 30, 100) -W $W -H $H -Mem $mem -MemMsg 'freed 2.5 GB')
    if ($frame.Count -ne $H - 1) { throw "frame ${W}x${H}: expected $($H - 1) lines, got $($frame.Count)" }
    $bad = $frame[0..($H - 3)] | Where-Object { (Get-VisLen $_) -ne $W }
    if ($bad) { throw "frame ${W}x${H}: ragged lines (visible width != $W):`n$($bad -join "`n")" }
}

# --- memory breakdown sanity ---
. "$PSScriptRoot\memory.ps1"
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
