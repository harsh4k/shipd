# shipd memory panel + free-RAM action (RAMMap-lite)

Date: 2026-07-05 · Status: approved

## Problem

Windows fills RAM with standby cache; Task Manager says "16 GB used" with no
explanation, and games/apps stutter when the cache won't release. Users reach
for Sysinternals RAMMap for two things: the memory breakdown, and
"Empty Standby List". shipd should cover both, in the live dashboard.

## Decisions (from brainstorming)

- **Scope**: diagnose + fix. No per-file page detail (that stays RAMMap's job).
- **Manual only**: the free action is triggered only by a human in the
  dashboard. The scheduled snapshot/report tasks NEVER purge memory.
- **Dashboard-first**: hotkey `f` in the live dashboard is the front door.
  `shipd free` exists as the elevated helper the dashboard invokes (and for
  scripting), `shipd mem` prints the breakdown read-only.
- **Elevation**: purging requires admin (SeProfileSingleProcessPrivilege).
  Unelevated `shipd free` self-elevates via UAC prompt (`Start-Process -Verb RunAs`).
- **What "free" does**: purge the standby list only
  (`NtSetSystemInformation(SystemMemoryListInformation, MemoryPurgeStandbyList)`)
  — the same call RAMMap/ISLC make. No working-set trimming (causes page-in
  churn that hurts more than it helps).

## Components

### memory.ps1 (new)

- `Get-MemoryBreakdown` — no admin. Returns `[pscustomobject]` with GB values:
  `total, in_use, standby, modified, free` from perf counters:
  `\Memory\Standby Cache Normal Priority Bytes` + `Reserve Bytes` + `Core Bytes`,
  `\Memory\Modified Page List Bytes`, `\Memory\Free & Zero Page List Bytes`;
  total from `Win32_OperatingSystem`; in_use = total − standby − modified − free.
- `Clear-StandbyList` — admin. P/Invoke `ntdll!NtSetSystemInformation` class 80
  command 4 (purge standby), after enabling `SeProfileSingleProcessPrivilege`
  via `AdjustTokenPrivileges`. Same `Add-Type` pattern as activity.ps1.
  Returns freed bytes (standby before − after).

### shipd.ps1

- `mem` command: print breakdown.
- `free` command: breakdown → self-elevate if needed → purge → print
  "freed X GB" + breakdown after. The caller measures standby before/after via
  `Get-MemoryBreakdown` itself, so no data handoff from the elevated child.

### dashboard.ps1

- MEMORY section: 4-row bar split (in use / standby / modified / free),
  refreshed with the normal dashboard tick.
- Hotkey row becomes `q quit · g rescan git · f free ram`.
- On `f`: record standby-before, launch elevated purge, show
  `✓ freed X GB standby cache` banner in the MEMORY section (persists a few
  ticks), panel keeps refreshing with post-purge numbers. If the user cancels
  the UAC prompt, show `free ram cancelled` instead — not an error.

## Error handling

- Counter names are English-localized → wrap `Get-Counter` in try/catch and
  degrade to hiding the MEMORY section (dashboard must not crash on non-English
  Windows).
- UAC declined / purge failed → non-fatal message, dashboard continues.

## Testing

Extend test_shipd.ps1: `Get-MemoryBreakdown` parts are non-negative and sum to
≈ total (±10%). Purge path not unit-tested (needs admin + is a syscall);
verified manually via dashboard.

## Docs

README: MEMORY panel + `f` key + `shipd mem`/`shipd free` in the command
table; one-line note that freeing standby cache is non-destructive but first
launches after it may be marginally slower (cache re-reads from disk).
