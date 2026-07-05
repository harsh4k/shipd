# Verification Report: SHIPD Robustness under Non-US Cultures and Square Bracket Paths

## 1. Observation
1. **Interactive Commands Timeout**: Proposing commands to run tests or verify behavior via `run_command` timed out waiting for user response:
   - Command: `pwsh -ExecutionPolicy Bypass .\test_shipd.ps1`
     - Status: `Permission prompt for action 'command' ... timed out waiting for user response.`
   - Command: `pwsh -ExecutionPolicy Bypass -Command "[System.Threading.Thread]::CurrentThread.CurrentCulture = 'fi-FI'; . .\git_scan.ps1; Get-DayCommits -Repo ."`
     - Status: `Permission prompt for action 'command' ... timed out waiting for user response.`

2. **Code Inspection - Clock Rendering in `dashboard.ps1`**:
   - Lines 12-24 define `$script:DigitFont` mapping containing keys `'0'` through `'9'` and `':'`.
   - Line 27:
     ```powershell
     $chars = (Get-Date).ToString('HH:mm:ss').ToCharArray()
     ```
   - Line 29:
     ```powershell
     -join ($chars | ForEach-Object { $script:DigitFont["$_"][$r] + ' ' })
     ```

3. **Code Inspection - Dot-Sourcing in `shipd.ps1` and `test_shipd.ps1`**:
   - `shipd.ps1` Lines 12-16:
     ```powershell
     . (Join-Path $PSScriptRoot 'git_scan.ps1')
     . (Join-Path $PSScriptRoot 'activity.ps1')
     . (Join-Path $PSScriptRoot 'memory.ps1')
     . (Join-Path $PSScriptRoot 'report.ps1')
     . (Join-Path $PSScriptRoot 'dashboard.ps1')
     ```
   - `test_shipd.ps1` Line 3:
     ```powershell
     . "$PSScriptRoot\git_scan.ps1"
     ```

4. **Code Inspection - Date Formatting in `git_scan.ps1`**:
   - Lines 35-36:
     ```powershell
     $since = $Date.Date.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
     $until = $Date.Date.AddDays(1).ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
     ```

---

## 2. Logic Chain
1. **Culture-Sensitivity in `dashboard.ps1`**:
   - In .NET/PowerShell custom date/time format strings, `:` is replaced by the current culture's time separator character.
   - For cultures like `fi-FI` (Finnish) or `it-IT` (Italian), the time separator is `.` instead of `:`.
   - Under these cultures, `(Get-Date).ToString('HH:mm:ss')` will produce a string like `23.50.57`.
   - Since `.` is not present in `$script:DigitFont` keys, the lookup `$script:DigitFont["."]` returns `$null`.
   - Attempting to index `$null` via `[$r]` returns `$null`, which breaks the Big Clock display layout and character alignment in the console.

2. **Wildcard / Square Bracket Path Resolution**:
   - In PowerShell, dot-sourcing a script from a string path (e.g. `. "C:\path\to\script.ps1"`) evaluates the string as a path that may contain wildcards.
   - If the path contains square brackets (like `[Z+ All-Things]`), PowerShell treats the brackets as a wildcard character set pattern.
   - Wildcard matching fails because the directory is named literally `[Z+ All-Things]` rather than matching a single character from the range.
   - Consequently, dot-sourcing `. (Join-Path $PSScriptRoot 'git_scan.ps1')` crashes with a file-not-found/cmdlet-not-recognized error if the root folder contains square brackets.

3. **Git Scan Culture-Independence**:
   - `git_scan.ps1` properly formats date strings using `[System.Globalization.CultureInfo]::InvariantCulture`, ensuring git commands receive the standard ISO-8601 timestamps irrespective of system culture.

---

## 3. Caveats
- Since command execution timed out on user permission prompts, the bugs were verified by static analysis and logical deduction rather than terminal output logs.
- The rest of the codebase utilizes `-LiteralPath` (e.g. `Test-Path -LiteralPath`, `Get-ChildItem -LiteralPath`, `Get-Content -LiteralPath`, `Set-Content -LiteralPath`), which is robust against wildcard character issues.

---

## 4. Conclusion
- **Unit Tests (`test_shipd.ps1`)**: **FAIL** when run in a directory containing square brackets (e.g. `[Z+ All-Things]`) due to the dot-sourcing wildcard resolution error.
- **Git Commit Scanning under non-US cultures**: **PASS**. Properly uses invariant culture formatting.
- **Dashboard / Report command execution**:
  - **FAIL** under non-US cultures where the time separator is not `:` (e.g. `fi-FI`, `it-IT`) because clock rendering fails when looking up `.` in the digit font map.
  - **FAIL** when run in a directory containing square brackets due to the dot-sourcing wildcard resolution error.

### Actionable Mitigations
1. **Clock Rendering Fix** (in `dashboard.ps1`):
   Force invariant culture for the clock's format string:
   ```powershell
   $chars = (Get-Date).ToString('HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture).ToCharArray()
   ```
2. **Dot-Sourcing Path Fix** (in `shipd.ps1` and `test_shipd.ps1`):
   Cast paths to `FileInfo` objects using `Get-Item -LiteralPath` before dot-sourcing, which prevents wildcard expansion:
   ```powershell
   . (Get-Item -LiteralPath (Join-Path $PSScriptRoot 'git_scan.ps1'))
   ```

---

## 5. Verification Method
1. Set the system/thread culture to Finnish:
   ```powershell
   [System.Threading.Thread]::CurrentThread.CurrentCulture = 'fi-FI'
   (Get-Date).ToString('HH:mm:ss') # Returns dots (e.g., '12.00.00')
   ```
2. Create a folder named `[test_bracket]` inside the workspace, place a dummy script `hello.ps1` inside, and run:
   ```powershell
   . ".\[test_bracket]\hello.ps1" # Fails with a path resolution error
   . (Get-Item -LiteralPath ".\[test_bracket]\hello.ps1") # Succeeds
   ```
