# BRIEFING — 2026-07-05T18:15:00Z

## Mission
Investigate and diagnose why commits are no longer displayed on the shipd dashboard when run via PowerShell and CMD.

## 🔒 My Identity
- Archetype: Explorer
- Roles: Read-only investigator
- Working directory: C:\Users\krish\OneDrive\Desktop\[Z+ All-Things]\#Current Work\Forked-Projects\SHIPD-Harsh4K\shipd\.agents\teamwork_preview_explorer_diagnostic_1
- Original parent: aff5eb50-e556-475b-96aa-66fccb81c4c3
- Milestone: Diagnostic and Analysis Report

## 🔒 Key Constraints
- Read-only investigation — do NOT implement (do NOT edit or create any source code, tests, or config files, except agent files under the working directory)
- DO NOT run any build or test commands yourself. Just locate, read, and analyze the codebase.

## Current Parent
- Conversation ID: aff5eb50-e556-475b-96aa-66fccb81c4c3
- Updated: 2026-07-05T18:18:00Z

## Investigation State
- **Explored paths**: PROJECT.md, shipd.ps1, git_scan.ps1, install.ps1, dashboard.ps1, report.ps1, test_shipd.ps1
- **Key findings**:
  - `git_scan.ps1` formats the dates for Git log `--since` and `--until` using `.ToString('yyyy-MM-dd 00:00:00')` without specifying `[CultureInfo]::InvariantCulture`.
  - In non-US locales/cultures, the date/time format will use culture-specific time separators (such as `.` in Nordic regions) or different calendars (such as the Thai Buddhist or Hijri calendar), which Git cannot parse.
  - This malformed date query leads `git log` to return no output or fail, so commits are never retrieved.
  - The test suite in `test_shipd.ps1` only mocks inputs to `ConvertFrom-NumstatLog` and does not run real Git integration tests, allowing this issue to go unnoticed during automated tests.
- **Unexplored areas**: None, the core diagnostic is complete.

## Key Decisions Made
- Analyzed date parsing and culture-sensitive format issues as the root cause.
- Formulated a fix strategy using `[System.Globalization.CultureInfo]::InvariantCulture` to guarantee Gregorian/ISO-8601 formatting.

## Artifact Index
- C:\Users\krish\OneDrive\Desktop\[Z+ All-Things]\#Current Work\Forked-Projects\SHIPD-Harsh4K\shipd\.agents\teamwork_preview_explorer_diagnostic_1\ORIGINAL_REQUEST.md — Original request content
- C:\Users\krish\OneDrive\Desktop\[Z+ All-Things]\#Current Work\Forked-Projects\SHIPD-Harsh4K\shipd\.agents\teamwork_preview_explorer_diagnostic_1\handoff.md — Handoff report detailing diagnostics and fix strategy
