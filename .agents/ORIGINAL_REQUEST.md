# Original User Request

## Initial Request — 2026-07-05T18:13:19Z

Investigate and fix the issue where shipd no longer displays commits after adding command prompt (CMD) support.

Working directory: C:\Users\krish\OneDrive\Desktop\[Z+ All-Things]\#Current Work\Forked-Projects\SHIPD-Harsh4K\shipd
Integrity mode: development

## Requirements

### R1. Diagnose Commits Bug
Diagnose why commits are no longer showing up in shipd after the addition of command prompt support.

### R2. Resolve the Issue
Fix the underlying cause so that commits are correctly retrieved and displayed on the dashboard/report when run from both PowerShell and Command Prompt.

## Acceptance Criteria

### Verification
- [ ] Commits are correctly displayed on the dashboard when running shipd from PowerShell.
- [ ] Commits are correctly displayed on the dashboard when running shipd from Command Prompt (CMD) via shipd.cmd.
- [ ] Existing self-checks in test_shipd.ps1 pass without errors.
