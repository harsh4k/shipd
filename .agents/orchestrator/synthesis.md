# Explorer Synthesis: shipd Commits Bug Diagnosis

## Consensus
All three explorer subagents independently investigated the issues and reached a consensus on the root causes of the missing commits:
1. **Culture-Dependent Time/Date Format in Git Scan (Cited by Explorer 1, 2, 3)**:
   - In `git_scan.ps1`, the date bounds `$since` and `$until` are formatted using `$Date.Date.ToString('yyyy-MM-dd 00:00:00')`.
   - Without an invariant culture parameter, .NET/PowerShell converts the time separator `:` based on the current thread's culture (e.g. `.` in Finnish or Danish regional settings). 
   - This results in invalid formats (e.g. `2026-07-05 00.00.00`) which `git log` fails to parse, returning no commits.
   - Fix: Use a culture-invariant string formatter such as:
     `$Date.Date.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)`.

2. **Wildcard Brackets Path Bug in PowerShell Cmdlets (Cited by Explorer 2, 3)**:
   - The workspace path contains square brackets: `C:\Users\krish\OneDrive\Desktop\[Z+ All-Things]...`.
   - In PowerShell, file system cmdlets (`Get-Content`, `Set-Content`, `Add-Content`, `Test-Path`, `Split-Path`) treat square brackets `[` and `]` as wildcards unless invoked with the `-LiteralPath` parameter instead of the default implicit `-Path` parameter.
   - This causes:
     - `Get-Content` to fail when reading `config.json` in `shipd.ps1` (line 11).
     - `Split-Path` to fail when parsing `$repo` in `git_scan.ps1` (line 50).
     - `Test-Path` and `Get-Content` to fail when checking/reading `$LogPath` in `report.ps1` (lines 7, 9).
     - `Add-Content` to fail when writing snapshots in `shipd.ps1` (line 28).
     - `Set-Content` to fail when writing report text files in `shipd.ps1` (line 36).
   - Fix: Replace all implicit path uses with `-LiteralPath` for these cmdlets across all identified lines.

## Resolved Conflicts
- **Working Directory Mismatch (Explorer 2)**:
  - Explorer 2 noted that relative paths like `.` in `config.json` might resolve to the wrong process-level working directory during external `git.exe` calls in some scenarios.
  - Explorer 3 resolved this by showing that because `Get-Content` on `config.json` fails completely (due to the Wildcard Brackets bug), the config is never loaded, causing `$Config.git_roots` to be empty/null, which is the immediate cause of the scan failure. Resolving paths using `-LiteralPath` will successfully load `config.json` and resolve paths using their absolute form.
  - Reconciled Strategy: Implementing both `-LiteralPath` fixes and ensuring any path resolutions are robust is the cleanest path forward.

## Dissenting Views
- None. All three explorers agree on the culture-invariant formatting issue and the wildcard path expansion issue.

## Gaps
- None. The combination of culture-safe date formatting and `-LiteralPath` usage covers all observed failure modes in both PowerShell and Command Prompt wrapper environments.
