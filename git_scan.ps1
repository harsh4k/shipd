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

# Your commits on $Date across every local branch.
# "Yours" = $AuthorEmails if given (config author_emails), else the repo's user.email;
# if neither is set, every author counts rather than silently showing nothing.
function Get-DayCommits {
    param([string]$Repo, [datetime]$Date = (Get-Date), [string[]]$AuthorEmails)
    $since = $Date.Date.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
    $until = $Date.Date.AddDays(1).ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
    # per repo, not once globally: includeIf lets work and personal folders use different emails
    if (-not $AuthorEmails) { $AuthorEmails = @(git -C $Repo config user.email 2>$null) }
    # "<email>" + fixed-strings = exact address match inside "Name <email>"; emails are case-insensitive
    $authorArgs = @($AuthorEmails | Where-Object { $_ } | ForEach-Object { "--author=<$_>" })
    if ($authorArgs) { $authorArgs += '--fixed-strings', '--regexp-ignore-case' }
    # no bare HEAD: it is fatal on an unborn/orphan branch; trailing -- so a file named like a ref can't confuse git
    $out = git -C $Repo log --branches @authorArgs "--since=$since" "--until=$until" --pretty=format:"COMMIT|%h|%s" --numstat -- 2>$null
    if (-not $out) { return @() }
    ConvertFrom-NumstatLog -Lines @($out)
}

# Every repo under the config roots with commits on $Date, plus per-repo totals.
function Get-DayRepoCommits {
    param($Config, [datetime]$Date = (Get-Date))
    # linked worktrees share their main checkout's branches: count each commit once, first repo found wins
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($root in $Config.git_roots) {
        foreach ($repo in Find-Repos -Root $root) {
            $commits = @(Get-DayCommits -Repo $repo -Date $Date -AuthorEmails $Config.author_emails |
                Where-Object { $seen.Add("$($_.Hash)|$($_.Message)") })
            if (-not $commits.Count) { continue }
            [pscustomobject]@{
                Path = $repo; Name = [System.IO.Path]::GetFileName($repo)
                Commits = $commits; NetLines = ($commits | Measure-Object NetLines -Sum).Sum
            }
        }
    }
}
