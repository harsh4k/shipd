# Handoff Report: Diagnosis of Missing Commits and Activity Snapshots on the shipd Dashboard

This report diagnoses why commits and activity snapshots are not displayed on the `shipd` dashboard when run under PowerShell and CMD.

## 1. Observation
We analyzed the following files in the project root (`C:\Users\krish\OneDrive\Desktop\[Z+ All-Things]\#Current Work\Forked-Projects\SHIPD-Harsh4K\shipd`):
* `shipd.ps1`
* `git_scan.ps1`
* `dashboard.ps1`
* `report.ps1`
* `install.ps1`
* `test_shipd.ps1`

### Exact Findings:
1. **Wildcard Path Bug in PowerShell File-System Cmdlets:**
   The workspace path is `C:\Users\krish\OneDrive\Desktop\[Z+ All-Things]\#Current Work\Forked-Projects\SHIPD-Harsh4K\shipd`, which contains square brackets `[` and `]`.
   PowerShell's file-system cmdlets like `Get-Content`, `Set-Content`, `Add-Content`, `Test-Path`, and `Split-Path` implicitly use the `-Path` parameter. When the path contains square brackets, PowerShell treats them as wildcard characters (character sets). Because no literal wildcard expansion matches the pattern correctly, the cmdlets fail or throw non-terminating errors.
   Specifically:
   - In `shipd.ps1` line 11:
     ```powershell
     $config = Get-Content (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
     ```
     `Get-Content` fails to load `config.json` because `$PSScriptRoot` contains brackets, resulting in `$config = $null`.
   - In `git_scan.ps1` line 50:
     ```powershell
     Path = $repo; Name = Split-Path $repo -Leaf
     ```
     `Split-Path` fails to resolve `$repo` (which contains brackets), causing `Name` to be blank or the pipeline to error.
   - In `report.ps1` line 7 & 9:
     ```powershell
     if (-not (Test-Path $LogPath)) { return $null }
     $snaps = @(Get-Content $LogPath | ForEach-Object { $_ | ConvertFrom-Json } |
     ```
     `Test-Path` and `Get-Content` fail to check/read `$LogPath`, meaning `Get-DaySnapSummary` always returns `$null` (hence "no snapshots yet" and no activity data displayed).
   - In `shipd.ps1` line 28 & 36:
     ```powershell
     ($snap | ConvertTo-Json -Compress) | Add-Content $logPath
     Format-ReportText $data | Set-Content (Join-Path $reportsDir "$($data.Day).txt")
     ```
     `Add-Content` and `Set-Content` fail to write/log data correctly.

2. **Culture-Dependent Time Separator Bug in Git Scans:**
   In `git_scan.ps1` line 35-37:
   ```powershell
   $since = $Date.Date.ToString('yyyy-MM-dd 00:00:00')
   $until = $Date.Date.AddDays(1).ToString('yyyy-MM-dd 00:00:00')
   $out = git -C $Repo log "--since=$since" "--until=$until" --pretty=format:"COMMIT|%h|%s" --numstat 2>$null
   ```
   Under non-US locales/cultures where the time separator is not a colon `:` (such as Finnish `fi-FI` which uses `.`), `.ToString('yyyy-MM-dd 00:00:00')` evaluates `:` to the culture's time separator (e.g. `2026-07-05 00.00.00`).
   Passing `--since="yyyy-MM-dd 00.00.00"` causes `git log` to fail parsing the date argument. Due to the `2>$null` redirection, this error is completely swallowed and `$out` is returned as empty, silently yielding no commits.

---

## 2. Logic Chain
1. **Wildcard Expansion Failure:**
   - The user runs `shipd` from CMD or PowerShell.
   - `shipd.ps1` attempts to run `Get-Content` on the path of `config.json`.
   - Because the project path has brackets `[Z+ All-Things]`, `Get-Content` fails to read `config.json` and throws an error.
   - `$config` remains `$null`.
   - When the dashboard or report runs, `$Config.git_roots` evaluates to `$null`.
   - `Get-DayRepoCommits` loops over `$Config.git_roots` (which is empty), finding zero git repositories. Hence, no commits are displayed.
   - In addition, the logging (`Add-Content`) and reading (`Get-Content`/`Test-Path`) of snapshots fail, making the dashboard show no snapshots.

2. **Git Date Range Parsing Failure:**
   - If a valid `config.json` was loaded, the script retrieves git repositories under the roots.
   - In `Get-DayCommits`, the script formats `$since` and `$until` using `$Date.Date.ToString('yyyy-MM-dd 00:00:00')`.
   - In cultures with a non-colon time separator, the string outputs with the localized separator (e.g. `00.00.00`).
   - Git parses the command arguments, encounters the unsupported time separator, and fails.
   - The stderr is redirected to `$null`, returning an empty list of commits.

---

## 3. Caveats
- We assumed that `git` is installed and present in the system environment `PATH` for both CMD and PowerShell. If `git` is missing completely from the environment, it would also cause zero commits, but the primary logic issues above will block it regardless of `git` availability.

---

## 4. Conclusion
To restore display of commits and activity snapshots, the worker must implement the following fixes:

### 1. Fix PowerShell Wildcard Path Resolution
Replace all implicit `-Path` parameters in file-system operations with `-LiteralPath` (which prevents wildcard interpretation of `[` and `]`).

* **`shipd.ps1` (Line 11):**
  *Before:*
  ```powershell
  $config = Get-Content (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
  ```
  *After:*
  ```powershell
  $config = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
  ```

* **`shipd.ps1` (Line 28):**
  *Before:*
  ```powershell
  ($snap | ConvertTo-Json -Compress) | Add-Content $logPath
  ```
  *After:*
  ```powershell
  ($snap | ConvertTo-Json -Compress) | Add-Content -LiteralPath $logPath
  ```

* **`shipd.ps1` (Line 36):**
  *Before:*
  ```powershell
  Format-ReportText $data | Set-Content (Join-Path $reportsDir "$($data.Day).txt")
  ```
  *After:*
  ```powershell
  Format-ReportText $data | Set-Content -LiteralPath (Join-Path $reportsDir "$($data.Day).txt")
  ```

* **`git_scan.ps1` (Line 50):**
  *Before:*
  ```powershell
  Path = $repo; Name = Split-Path $repo -Leaf
  ```
  *After:*
  ```powershell
  Path = $repo; Name = Split-Path -LiteralPath $repo -Leaf
  ```

* **`report.ps1` (Line 7):**
  *Before:*
  ```powershell
  if (-not (Test-Path $LogPath)) { return $null }
  ```
  *After:*
  ```powershell
  if (-not (Test-Path -LiteralPath $LogPath)) { return $null }
  ```

* **`report.ps1` (Line 9):**
  *Before:*
  ```powershell
  $snaps = @(Get-Content $LogPath | ForEach-Object { $_ | ConvertFrom-Json } |
  ```
  *After:*
  ```powershell
  $snaps = @(Get-Content -LiteralPath $LogPath | ForEach-Object { $_ | ConvertFrom-Json } |
  ```

### 2. Fix Date Format Invariance
Ensure the date string is formatted in a culture-invariant manner using backslash-escaped colons in the format string.

* **`git_scan.ps1` (Lines 35-36):**
  *Before:*
  ```powershell
  $since = $Date.Date.ToString('yyyy-MM-dd 00:00:00')
  $until = $Date.Date.AddDays(1).ToString('yyyy-MM-dd 00:00:00')
  ```
  *After:*
  ```powershell
  $since = $Date.Date.ToString('yyyy-MM-dd 00\:00\:00')
  $until = $Date.Date.AddDays(1).ToString('yyyy-MM-dd 00\:00\:00')
  ```

---

## 5. Verification Method
To verify the fix:
1. **Unit/Integration Tests:**
   Run the project check command:
   ```powershell
   pwsh .\test_shipd.ps1
   ```
   All checks should pass.
2. **Manual verification under square brackets path:**
   Open a PowerShell 7 shell in the current directory (`C:\Users\krish\OneDrive\Desktop\[Z+ All-Things]\#Current Work\Forked-Projects\SHIPD-Harsh4K\shipd`).
   Configure `config.json` with the current workspace path (or a directory containing a test Git repository with commits from today).
   Run the dashboard:
   ```powershell
   pwsh .\shipd.ps1
   ```
   Ensure the dashboard correctly shows the repository name and commits list.
3. **Culture verification:**
   Set the current shell thread culture to a non-US locale (e.g., Finnish or German) and verify that `git_scan.ps1`'s `Get-DayCommits` retrieves commits without failing:
   ```powershell
   [System.Threading.Thread]::CurrentThread.CurrentCulture = 'fi-FI'
   . .\git_scan.ps1
   Get-DayCommits -Repo . -Date (Get-Date)
   ```
   This should return the list of commits rather than an empty array.
