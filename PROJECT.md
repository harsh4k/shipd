# Project: shipd-commits-fix

## Architecture
`shipd` is a daily dev and activity reporter written in PowerShell.
It consists of several modules:
- `shipd.ps1`: The main entry point script.
- `git_scan.ps1`: Scans git repository for commits.
- `dashboard.ps1`: Renders the dashboard showing activity and commits.
- `report.ps1`: Generates report content.
- `activity.ps1` & `memory.ps1`: Collect activity and system metrics.
- `install.ps1`: Configures/installs the tool and creates wrappers like `shipd.cmd` for CMD support.
- `test_shipd.ps1`: Automated tests/self-checks.

## Code Layout
- Project root: `C:\Users\krish\OneDrive\Desktop\[Z+ All-Things]\#Current Work\Forked-Projects\SHIPD-Harsh4K\shipd`
- Core scripts: `shipd.ps1`, `git_scan.ps1`, `dashboard.ps1`, `report.ps1`, `activity.ps1`, `memory.ps1`
- Installation script: `install.ps1`
- Test script: `test_shipd.ps1`
- Agent metadata: `.agents/orchestrator`

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | M1: Diagnostic Exploration | Explore how CMD support is implemented, locate where commits retrieval fails, and recommend a fix strategy. | None | DONE |
| 2 | M2: Implementation & Fix | Implement the fix so commits are correctly retrieved and displayed from both PowerShell and Command Prompt. Ensure existing tests pass. | M1 | IN_PROGRESS |
| 3 | M3: Review & Verification | Review correctness, completeness, and perform challenger/auditor checks to verify integrity and robustness. | M2 | PLANNED |

## Interface Contracts
- `git_scan.ps1` retrieves git commits and activity, and feeds this into `dashboard.ps1` / `report.ps1`.
- `shipd.cmd` runs the PowerShell script `shipd.ps1` in a PowerShell host.
- The environment state (like current working directory or Git environment variables) must correctly propagate from the wrapper `shipd.cmd` to PowerShell scripts.
