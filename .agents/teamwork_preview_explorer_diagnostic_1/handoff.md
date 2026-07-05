# Handoff Report — Commit Retrieval Diagnostic

## 1. Observation

During the read-only exploration and diagnosis of the codebase, the following files and sections were analyzed:

1. **`git_scan.ps1` (Lines 33–40)**:
   This file retrieves the commits for the current day.
   ```powershell
   33: function Get-DayCommits {
   34:     param([string]$Repo, [datetime]$Date = (Get-Date))
   35:     $since = $Date.Date.ToString('yyyy-MM-dd 00:00:00')
   36:     $until = $Date.Date.AddDays(1).ToString('yyyy-MM-dd 00:00:00')
   37:     $out = git -C $Repo log "--since=$since" "--until=$until" --pretty=format:"COMMIT|%h|%s" --numstat 2>$null
   38:     if (-not $out) { return @() }
   39:     ConvertFrom-NumstatLog -Lines @($out)
   40: }
   ```

2. **`test_shipd.ps1` (Lines 5–19)**:
   This file defines the test cases for `ConvertFrom-NumstatLog` by mocking static input rather than executing actual `git` integration commands or validating the behavior of `Get-DayCommits` or `Get-DayRepoCommits`.
   ```powershell
   5: # --- numstat parser ---
   6: $lines = @(
   7:     'COMMIT|abc1234|fix: the thing',
   8:     '10	3	foo.py',
   9:     '-	-	img.png',
   10:     '',
   11:     'COMMIT|def5678|msg|with|pipes',
   12:     '0	5	bar.py'
   13: )
   14: $c = @(ConvertFrom-NumstatLog -Lines $lines)
   ```

## 2. Logic Chain

- **Step 1**: In `git_scan.ps1` (Line 35 & 36), the date limits `$since` and `$until` are generated via `$Date.Date.ToString('yyyy-MM-dd 00:00:00')`.
- **Step 2**: This `.ToString()` call does not specify a culture-invariant parameter (i.e. `[System.Globalization.CultureInfo]::InvariantCulture`). Therefore, .NET/PowerShell formats the dates using the system's local regional settings/culture.
- **Step 3**: On systems with non-US regional settings (e.g. Nordic cultures using `.` instead of `:` as the time separator, or calendars such as Thai Buddhist where the year represents current Gregorian year + 543), the formatted string will be malformed (e.g., `2026-07-05 00.00.00`) or in the far future (e.g., `2569-07-05 00:00:00`).
- **Step 4**: When the `git` command runs on Line 37 using `git -C $Repo log "--since=$since" "--until=$until" ...`, it receives these culture-specific or future date strings.
- **Step 5**: Because Git does not support non-Gregorian calendars or non-standard time separators (like `.`), the query either fails or returns an empty output, meaning no commits are retrieved.
- **Step 6**: The command-not-found or invalid date warnings are discarded via `2>$null` (Line 37), causing the failure to happen silently.
- **Step 7**: The mock test cases in `test_shipd.ps1` (Lines 5–19) feed static arrays of strings directly to `ConvertFrom-NumstatLog` rather than calling `Get-DayCommits`, which is why the tests pass successfully while the script fails in actual environments.

## 3. Caveats

- We assume Git is correctly installed and configured in the system PATH for the environment where `shipd` is executed.
- We assume that the user's repository actually has commits made on the current system date.

## 4. Conclusion

The root cause of the missing commits is culture-sensitive date formatting in `git_scan.ps1`.
To resolve this, we must ensure that the date/time strings `$since` and `$until` are formatted in a culture-invariant manner. Additionally, we can omit the space from the format to make the arguments simpler and less shell-sensitive.

### Proposed Code Changes

#### `git_scan.ps1`
Modify the date-formatting lines to explicitly use `[System.Globalization.CultureInfo]::InvariantCulture` and format with the standard ISO-8601 `T` separator:

**Before (Lines 35–36)**:
```powershell
    $since = $Date.Date.ToString('yyyy-MM-dd 00:00:00')
    $until = $Date.Date.AddDays(1).ToString('yyyy-MM-dd 00:00:00')
```

**After**:
```powershell
    $since = $Date.Date.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
    $until = $Date.Date.AddDays(1).ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
```

## 5. Verification Method

To verify the fix:
1. Temporarily configure the local regional settings of the environment to a culture like Finnish (`fi-FI`) or Thai (`th-TH`).
2. Run `Get-DayCommits` or `Get-DayRepoCommits` on a repository known to have commits on the target day.
   - If using the old code, no commits will be returned (`$out` is empty/null).
   - If using the new code, the commits will be retrieved and parsed correctly.
3. Run the automated tests (`.\test_shipd.ps1`) to ensure no regressions are introduced in the parsers or metrics gathering.
