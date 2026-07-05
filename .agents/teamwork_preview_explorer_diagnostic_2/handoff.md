# Handoff Report: Diagnosing Missing Commits on shipd Dashboard

## 1. Observation

Direct observations and file references in `C:\Users\krish\OneDrive\Desktop\[Z+ All-Things]\#Current Work\Forked-Projects\SHIPD-Harsh4K\shipd`:

- **`git_scan.ps1` (lines 35-36)**:
  ```powershell
  $since = $Date.Date.ToString('yyyy-MM-dd 00:00:00')
  $until = $Date.Date.AddDays(1).ToString('yyyy-MM-dd 00:00:00')
  ```
- **`git_scan.ps1` (line 37)**:
  ```powershell
  $out = git -C $Repo log "--since=$since" "--until=$until" --pretty=format:"COMMIT|%h|%s" --numstat 2>$null
  ```
- **`git_scan.ps1` (lines 5-11)**:
  ```powershell
  function Find-Repos {
      param([string]$Root, [int]$Depth = 3)
      if ($Depth -lt 0 -or -not (Test-Path -LiteralPath $Root)) { return }
      if (Test-Path -LiteralPath (Join-Path $Root '.git')) { return $Root }
      foreach ($dir in Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction SilentlyContinue) {
          if ($dir.Name -in 'node_modules', '.git') { continue }
          Find-Repos -Root $dir.FullName -Depth ($Depth - 1)
      }
  }
  ```
- **`git_scan.ps1` (lines 45-47)**:
  ```powershell
  foreach ($root in $Config.git_roots) {
      foreach ($repo in Find-Repos -Root $root) {
          $commits = @(Get-DayCommits -Repo $repo -Date $Date)
  ```
- **`test_shipd.ps1` (lines 5-19)**:
  Tests `ConvertFrom-NumstatLog` by feeding hardcoded mock string lines, but does **not** test `Get-DayCommits` or invoke the native `git` command with formatted date filters.
- **`install.ps1` (line 38)**:
  Generates `shipd.cmd` containing:
  ```cmd
  @echo off
  "%pwsh%" -NoProfile -File "%LOCALAPPDATA%\shipd\shipd.ps1" %*
  ```

---

## 2. Logic Chain

### Bug A: Culture-Dependent Date String (Primary Cause)
1. **Observation 1**: `git_scan.ps1` constructs date strings `$since` and `$until` using `$Date.Date.ToString('yyyy-MM-dd 00:00:00')`.
2. **Observation 2**: In .NET custom date formatting, the `:` character is interpreted as the current thread's culture/locale time separator. On machines with cultures such as Danish (`da-DK`), Finnish (`fi-FI`), or Italian (`it-IT`), the `:` character is substituted with a dot `.`, producing dates like `2026-07-05 00.00.00`.
3. **Observation 3**: The git command uses these strings directly: `git -C $Repo log "--since=$since" "--until=$until"`.
4. **Logical Inference**: Git's date parser does not recognize times formatted with dots (e.g. `00.00.00`) and fails with an error (e.g., `fatal: invalid date format`). Since stderr is redirected to `$null` (via `2>$null`), the command fails silently, returning an empty `$out` to `Get-DayCommits`, which results in `@()` commits.

### Bug B: Relative Path Working Directory Mismatch (Secondary Cause)
1. **Observation 1**: `Find-Repos` evaluates the specified `$Root` from `config.json`. If `git_roots` is set to `["."]` or relative paths, `Find-Repos` returns a relative path (e.g., `.`).
2. **Observation 2**: PowerShell maintains a logical working directory `$PWD`, which updates when a user runs `cd`. However, changing directories inside PowerShell does **not** update the process-level current working directory (retrieved by `[System.IO.Directory]::GetCurrentDirectory()`).
3. **Observation 3**: External executables like `git.exe` operate using the process-level working directory. When `git -C .` is executed, it resolves `.` relative to the process's working directory rather than PowerShell's `$PWD`.
4. **Logical Inference**: If the user runs `shipd` from PowerShell after navigating to a different repository, `Find-Repos` locates `.git` using PowerShell's `$PWD` and returns `.`. The external `git` command, however, runs in the old process directory, fails to locate the correct repository, and returns no commits.

---

## 3. Caveats

- We assume the user has a functioning `git` executable installed and accessible within the system/user environment `PATH`. If `git` is missing completely, no commits will be displayed (which is the expected behavior, though silently ignored by `2>$null`).
- We assume that standard scheduled tasks running under Windows task scheduler have a working directory configured properly. If they do not, Bug B would also affect the daily scheduled report, but resolving it to an absolute path completely mitigates this.

---

## 4. Conclusion

The missing commits issue is caused by a combination of:
1. **Culture-sensitive formatting of time separators** (the `:` character) when constructing Git `--since` and `--until` date arguments, causing Git to fail parsing dates in non-US locales.
2. **Logical vs process directory mismatch** when resolving relative paths in `Find-Repos`, which causes external `git.exe` to look in the wrong directory.

### Proposed Fixes:
1. **Culture-Safe & Space-Free Date Formatting**:
   In `git_scan.ps1` lines 35-36, change:
   ```powershell
   $since = $Date.Date.ToString('yyyy-MM-dd 00:00:00')
   $until = $Date.Date.AddDays(1).ToString('yyyy-MM-dd 00:00:00')
   ```
   to:
   ```powershell
   $since = $Date.Date.ToString('yyyy-MM-dd') + 'T00:00:00'
   $until = $Date.Date.AddDays(1).ToString('yyyy-MM-dd') + 'T00:00:00'
   ```
   This generates a standard ISO 8601 string `YYYY-MM-DDT00:00:00` without culture-sensitive colon expansion, avoiding space-splitting issues and ensuring Git parses it correctly.

2. **Absolute Path Resolution in `Find-Repos`**:
   In `git_scan.ps1` at the beginning of `Find-Repos`, resolve `$Root` to its absolute path:
   ```powershell
   function Find-Repos {
       param([string]$Root, [int]$Depth = 3)
       if ($Depth -lt 0 -or -not (Test-Path -LiteralPath $Root)) { return }
       $resolvedRoot = (Get-Item $Root).FullName
       if (Test-Path -LiteralPath (Join-Path $resolvedRoot '.git')) { return $resolvedRoot }
       foreach ($dir in Get-ChildItem -LiteralPath $resolvedRoot -Directory -Force -ErrorAction SilentlyContinue) {
           if ($dir.Name -in 'node_modules', '.git') { continue }
           Find-Repos -Root $dir.FullName -Depth ($Depth - 1)
       }
   }
   ```
   This converts relative paths to fully-qualified paths using the active PowerShell provider location, guaranteeing that `git -C` is given an absolute directory.

---

## 5. Verification Method

The implementation agent (implementer) should verify the fix using the following steps:
1. **Automated Tests**:
   - Run `.\test_shipd.ps1` to ensure that existing tests and parsers still function.
2. **Manual Dashboard Check (PowerShell & CMD)**:
   - Temporarily set system locale/culture to Finnish (`fi-FI`) or Danish (`da-DK`).
   - Run `shipd` from both PowerShell and Command Prompt (`cmd.exe`).
   - Verify that the "GIT TODAY" panel correctly renders recent commits instead of showing "no commits today".
3. **Relative Path Check**:
   - In `config.json`, configure `git_roots` to contain `["."]`.
   - Open PowerShell, navigate to a directory containing a Git repository that has a commit today.
   - Run `shipd`.
   - Confirm that the commits in that repository are displayed correctly.
