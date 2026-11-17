# CLAUDE.md — shipd

Instructions for coding agents working in this repository.

## What this is

shipd is a daily dev + activity report for Windows, in pure PowerShell 7. A scheduled task takes a
silent snapshot every N minutes (focused app, idle time, known games running). A daily task builds a
report that combines those snapshots with today's git commits across the user's project folders.
`shipd` with no arguments opens a live full-screen terminal dashboard.

No dependencies, no accounts, no network, no telemetry. All data stays in the install folder.

## Stack

| Thing | What shipd uses |
|---|---|
| Language | PowerShell 7+ (`pwsh`). `$PSStyle` is required, so Windows PowerShell 5.1 can't run shipd |
| Installer | `install.ps1`, which **must stay 5.1-compatible** (no `&&`, no ternary, no `??`) because it runs via `irm \| iex` in whatever shell the user has |
| OS APIs | Win32 through `Add-Type` P/Invoke (user32 for focus/idle, ntdll/advapi32 for the standby purge) |
| Scheduling | Windows Task Scheduler, launched through `hidden.vbs` so no console window flashes |
| Storage | `snapshots.jsonl` (one JSON object per line, append-only), `reports\<yyyy-MM-dd>.txt`, `config.json` |
| Git | System `git` via native calls. No libraries |

## File map

```
shipd.ps1       Entry point and command switch (dashboard, snapshot, report, mem, free, install, schedule, ...)
git_scan.ps1    Find-Repos, ConvertFrom-NumstatLog, Get-DayCommits, Get-DayRepoCommits
activity.ps1    Focused process, idle seconds, system stats, Get-ActivitySnapshot
memory.ps1      Memory breakdown (perf counters) + Clear-StandbyList (admin only, manual only)
report.ps1      Get-DaySnapSummary, Get-ReportData, Show-Dashboard (colored), Format-ReportText (plain)
dashboard.ps1   Live TUI: panels, big clock, sparkline, key loop (q / g / f)
install.ps1     One-line installer: pwsh check, download, CMD wrapper, profiles, PATH, schedule
hidden.vbs      Windowless launcher for scheduled tasks. Do not delete
test_shipd.ps1  Self-checks (parser, repo scan, frame geometry, memory sanity)
config.json     Shipped defaults. The installer rewrites git_roots on a fresh install
```

## Commands

```powershell
pwsh -NoProfile -File .\test_shipd.ps1      # tests; prints "all checks passed"
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1   # lint, must be clean
.\shipd.ps1                                 # live dashboard (needs a 110x24 window)
.\shipd.ps1 report                          # today's report
.\shipd.ps1 snapshot                        # one snapshot
```

The tests run under pwsh on Linux/macOS too. Anything that touches Win32, Task Scheduler or perf
counters only works on Windows, so verify it on a Windows machine or in the Windows CI job
(`.github/workflows/ci.yml`: lint, an ASCII check and a 5.1 parse of `install.ps1` on Windows;
tests on Windows and Ubuntu; a Windows smoke run of `snapshot`, `report` and `mem`). Prefer a
`SuppressMessageAttribute` at the one site over a repo-wide exclusion; a new exclusion in
`PSScriptAnalyzerSettings.psd1` needs a one-line reason.
- `install.ps1` stays **pure ASCII** (5.1 reads BOM-less files as ANSI; CI enforces it).

## Conventions

- **Always use `-LiteralPath`** with `Test-Path`, `Get-Content`, `Set-Content`, `Add-Content`,
  `New-Item` and `Remove-Item`. Install paths can contain `[` and `]`, which `-Path` treats as
  wildcards. This was the root cause of a real "no commits in CMD" bug.
- **Format dates for git with `InvariantCulture`.** Some locales use `.` as the time separator, and
  git silently returns nothing for those strings.
- Background tasks never elevate and never touch memory. `free` is manual only (CLI or `f` key).
- Every reader of `snapshots.jsonl` must tolerate a torn or corrupt line and skip it, and every
  write goes through `Add-SnapshotLine`, which starts a fresh line after a torn one. A crash
  mid-append must never break the report or swallow the next snapshot.
- Elevation goes through `Invoke-ElevatedFree` (memory.ps1). Only ERROR_CANCELLED counts as
  "user declined"; any other failure is reported as a failure.
- The saved report stays plain text. Colors are for the terminal only.
- Dashboard frame lines must be exactly `W` visible characters wide. The geometry test enforces this.
- Match the existing style: small focused functions, comments that explain *why*, no new modules or
  dependencies without asking.
- Never commit personal data or machine-specific paths. `snapshots.jsonl` and `reports/` are
  gitignored, and `config.json` must keep the documented default `git_roots`.
- Never commit agent scratch files (`.agents/`, `PROJECT.md`, `ORIGINAL_REQUEST.md`, plans, handoffs).

## Privacy contract

Stored: timestamp, focused process name, idle seconds, and the names of configured games that are
running. Nothing else. No window titles, no keystrokes, no network calls. Any change that stores more
must be opt-in and documented in the README's Privacy section.

## Workflow

- Work on a feature branch and land it through a focused PR. Never push to `master`, because the
  one-line installer deploys `master` to every user who re-runs it.
- Before calling a change done: tests pass, lint is clean, and for Windows-only behavior say
  whether it was verified on Windows or is **unverified**.

## Roadmap

1. ~~Repo hygiene~~ done: agent scratch files removed, MIT LICENSE.
2. ~~Correctness~~ done: torn snapshot lines, your commits only, all branches, `-LiteralPath`, `free` failures.
3. ~~CI~~ done: GitHub Actions lint, tests on Windows + Ubuntu, Windows smoke run. Running
   `install.ps1` end to end under 5.1 in CI comes with step 4 (it needs a local-source option).
4. Install lifecycle: `shipd uninstall`, versioned installs from release tags, fix the CMD
   refresh helper.
5. Dashboard polish: responsive panel widths, live CPU % instead of cumulative CPU seconds, a
   palette shared with the report, `NO_COLOR` support.
