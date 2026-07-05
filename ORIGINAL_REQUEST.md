# Original User Request

## Initial Request — 2026-07-06T00:03:52+05:30

Investigate and resolve why commits are displayed in PowerShell but not in Command Prompt (CMD) when running shipd.

Working directory: C:\Users\krish\OneDrive\Desktop\[Z+ All-Things]\#Current Work\Forked-Projects\SHIPD-Harsh4K\shipd
Integrity mode: development

## Requirements

### R1. Diagnose CMD Commits Bug
Diagnose why commits are not showing up when shipd is run from Command Prompt (CMD) via shipd.cmd, whereas they do show up in PowerShell.

### R2. Resolve CMD Commits Issue
Fix the underlying issue so that commits show up correctly in both CMD and PowerShell.

## Acceptance Criteria

### Verification
- [ ] Commits are correctly displayed on the dashboard/report when running shipd from Command Prompt (CMD) via shipd.cmd.
- [ ] Existing self-checks in test_shipd.ps1 pass without errors.
