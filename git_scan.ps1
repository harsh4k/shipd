# Repo discovery + today's commits. System git via native calls, no libraries.

function Find-Repos {
    param([string]$Root, [int]$Depth = 3)
    if ($Depth -lt 0 -or -not (Test-Path -LiteralPath $Root)) { return }
    if (Test-Path -LiteralPath (Join-Path $Root '.git')) { return $Root }
    foreach ($dir in Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction SilentlyContinue) {
        if ($dir.Name -in 'node_modules', '.git') { continue }
        Find-Repos -Root $dir.FullName -Depth ($Depth - 1)
    }
}

# Parses `git log --pretty=format:"COMMIT|%h|%s" --numstat` output lines.
function ConvertFrom-NumstatLog {
    param([string[]]$Lines)
    $commits = @()
    $cur = $null
    foreach ($line in $Lines) {
        if ($line -like 'COMMIT|*') {
            $parts = $line -split '\|', 3
            $cur = [pscustomobject]@{ Hash = $parts[1]; Message = $parts[2]; Files = 0; NetLines = 0 }
            $commits += $cur
        }
        elseif ($cur -and $line -match '^(\d+|-)\s+(\d+|-)\s+\S') {
            $cur.Files++
            # numstat shows "-" for binary files: count the file, skip line math
            if ($Matches[1] -ne '-') { $cur.NetLines += [int]$Matches[1] - [int]$Matches[2] }
        }
    }
    $commits
}

function Get-DayCommits {
    param([string]$Repo, [datetime]$Date = (Get-Date))
    $since = $Date.Date.ToString('yyyy-MM-dd 00:00:00')
    $until = $Date.Date.AddDays(1).ToString('yyyy-MM-dd 00:00:00')
    $out = git -C $Repo log "--since=$since" "--until=$until" --pretty=format:"COMMIT|%h|%s" --numstat 2>$null
    if (-not $out) { return @() }
    ConvertFrom-NumstatLog -Lines @($out)
}

# Every repo under the config roots with commits on $Date, plus per-repo totals.
function Get-DayRepoCommits {
    param($Config, [datetime]$Date = (Get-Date))
    foreach ($root in $Config.git_roots) {
        foreach ($repo in Find-Repos -Root $root) {
            $commits = @(Get-DayCommits -Repo $repo -Date $Date)
            if (-not $commits.Count) { continue }
            [pscustomobject]@{
                Path = $repo; Name = Split-Path $repo -Leaf
                Commits = $commits; NetLines = ($commits | Measure-Object NetLines -Sum).Sum
            }
        }
    }
}
