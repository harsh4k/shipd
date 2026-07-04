# Memory Panel + Free-RAM Action Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** RAMMap-lite for shipd — a live memory breakdown (in use / standby / modified / free) in the dashboard, plus an `f` hotkey / `shipd free` command that purges the Windows standby list and reports how much RAM was released.

**Architecture:** New `memory.ps1` holds the two primitives: `Get-MemoryBreakdown` (perf counters, no admin) and `Clear-StandbyList` (P/Invoke `NtSetSystemInformation`, admin). `shipd.ps1` gains `mem` and `free` commands; `free` self-elevates via UAC. `dashboard.ps1` renders a MEMORY section in the left panel and wires the `f` hotkey, measuring standby before/after around the elevated child to show "freed X GB".

**Tech Stack:** PowerShell 7, `Get-Counter`, `Add-Type` P/Invoke (same pattern as activity.ps1). Zero new dependencies.

## Global Constraints

- Pure PowerShell 7; no external binaries, no modules to install (spec: "zero-dependency ethos").
- The scheduled snapshot/report tasks NEVER purge memory — purge is only reachable via `shipd free` / dashboard `f` (spec: "Manual only").
- Purge = standby list only (`MemoryPurgeStandbyList = 4`). NO working-set trimming.
- Non-English Windows: counters may not exist → `Get-MemoryBreakdown` returns `$null`, every caller degrades gracefully (dashboard hides section; commands print "memory counters unavailable"). Dashboard must never crash.
- UAC declined = normal outcome, not an error.
- All dashboard lines must keep exact panel geometry (test_shipd.ps1 enforces visible width).

---

### Task 1: memory.ps1 — breakdown + purge primitives

**Files:**
- Create: `memory.ps1`
- Test: `test_shipd.ps1` (append section)

**Interfaces:**
- Consumes: nothing from other files (standalone; safe to dot-source anywhere).
- Produces:
  - `Get-MemoryBreakdown` → `[pscustomobject]@{ total; in_use; standby; modified; free }` — all `[double]` GB rounded to 2 dp, or `$null` when counters unavailable.
  - `Clear-StandbyList` → `[double]` GB freed (standby before − after). Throws on NT failure. Requires the process to already be elevated.

- [ ] **Step 1: Write the failing test** — append to `test_shipd.ps1` just above the final `Write-Output 'all checks passed'`:

```powershell
# --- memory breakdown sanity ---
. "$PSScriptRoot\memory.ps1"
$m = Get-MemoryBreakdown
if ($null -ne $m) {
    foreach ($p in 'total', 'in_use', 'standby', 'modified', 'free') {
        if ($m.$p -lt 0) { throw "memory: negative $p ($($m.$p))" }
    }
    $sum = $m.in_use + $m.standby + $m.modified + $m.free
    if ([math]::Abs($sum - $m.total) -gt $m.total * 0.1) {
        throw "memory: parts sum $sum GB but total is $($m.total) GB"
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.\test_shipd.ps1`
Expected: FAIL — `The term '...memory.ps1' is not recognized` / file not found.

- [ ] **Step 3: Write the implementation** — create `memory.ps1`:

```powershell
# Memory breakdown + standby-list purge (RAMMap-lite).
# Breakdown: perf counters, no admin. Purge: NtSetSystemInformation, admin only,
# and only ever invoked manually (shipd free / dashboard 'f') — never by scheduled tasks.

Add-Type -Namespace Win32 -Name Memory -MemberDefinition @'
[DllImport("ntdll.dll")]
public static extern int NtSetSystemInformation(int infoClass, ref int info, int length);
[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool OpenProcessToken(IntPtr proc, uint access, out IntPtr token);
[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool LookupPrivilegeValue(string host, string name, out long luid);
[StructLayout(LayoutKind.Sequential)]
public struct TOKEN_PRIVILEGES { public uint Count; public long Luid; public uint Attr; }
[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TOKEN_PRIVILEGES state, int len, IntPtr prev, IntPtr ret);
'@

function Get-MemoryBreakdown {
    # counter names are English; on localized Windows this fails -> $null, callers degrade
    try {
        $s = (Get-Counter -ErrorAction Stop -Counter @(
                '\Memory\Standby Cache Normal Priority Bytes'
                '\Memory\Standby Cache Reserve Bytes'
                '\Memory\Standby Cache Core Bytes'
                '\Memory\Modified Page List Bytes'
                '\Memory\Free & Zero Page List Bytes'
            )).CounterSamples
    }
    catch { return $null }
    $standby  = ($s | Where-Object Path -like '*standby*' | Measure-Object CookedValue -Sum).Sum
    $modified = ($s | Where-Object Path -like '*modified*').CookedValue
    $free     = ($s | Where-Object Path -like '*free & zero*').CookedValue
    $total    = (Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize * 1KB
    [pscustomobject]@{
        total    = [math]::Round($total / 1GB, 2)
        in_use   = [math]::Round(($total - $standby - $modified - $free) / 1GB, 2)
        standby  = [math]::Round($standby / 1GB, 2)
        modified = [math]::Round($modified / 1GB, 2)
        free     = [math]::Round($free / 1GB, 2)
    }
}

function Clear-StandbyList {
    # requires elevation; enables SeProfileSingleProcessPrivilege, then
    # SystemMemoryListInformation(80) / MemoryPurgeStandbyList(4) — same call RAMMap makes
    $before = Get-MemoryBreakdown
    $token = [IntPtr]::Zero
    $procH = [System.Diagnostics.Process]::GetCurrentProcess().Handle
    if (-not [Win32.Memory]::OpenProcessToken($procH, 0x28, [ref]$token)) {  # ADJUST_PRIVILEGES|QUERY
        throw 'OpenProcessToken failed'
    }
    $luid = [long]0
    [void][Win32.Memory]::LookupPrivilegeValue($null, 'SeProfileSingleProcessPrivilege', [ref]$luid)
    $tp = New-Object 'Win32.Memory+TOKEN_PRIVILEGES'
    $tp.Count = 1; $tp.Luid = $luid; $tp.Attr = 2  # SE_PRIVILEGE_ENABLED
    [void][Win32.Memory]::AdjustTokenPrivileges($token, $false, [ref]$tp, 0, [IntPtr]::Zero, [IntPtr]::Zero)
    $cmd = 4
    $status = [Win32.Memory]::NtSetSystemInformation(80, [ref]$cmd, 4)
    if ($status -ne 0) { throw ('NtSetSystemInformation failed: 0x{0:X8} (not elevated?)' -f $status) }
    $after = Get-MemoryBreakdown
    if ($before -and $after) { [math]::Round([math]::Max(0, $before.standby - $after.standby), 2) } else { [double]0 }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.\test_shipd.ps1`
Expected: `all checks passed`

- [ ] **Step 5: Commit**

```powershell
git add memory.ps1 test_shipd.ps1
git commit -m "feat: memory breakdown + standby-list purge primitives (memory.ps1)"
```

---

### Task 2: shipd.ps1 — `mem` and `free` commands

**Files:**
- Modify: `shipd.ps1:6` (ValidateSet), `shipd.ps1:2` (usage comment), `shipd.ps1:12-15` (dot-source block), switch body before the `'schedule', 'restart'` case (line ~55)

**Interfaces:**
- Consumes: `Get-MemoryBreakdown`, `Clear-StandbyList` (Task 1 signatures).
- Produces: `pwsh -NoProfile -File shipd.ps1 free` — purges when elevated, self-elevates otherwise; prints `freed X GB standby cache` + breakdown line. `shipd.ps1 mem` prints breakdown only. The dashboard (Task 3) launches `shipd.ps1 free` elevated and relies on it purging synchronously before exit.

- [ ] **Step 1: Wire the file in** — three small edits:

Line 2 usage comment becomes:

```powershell
# Usage: shipd [dashboard] | snapshot | report [date] | mem | free | list | install | schedule | start | stop | restart | unschedule
```

Line 6 ValidateSet becomes:

```powershell
    [ValidateSet('dashboard', 'snapshot', 'report', 'mem', 'free', 'list', 'install', 'schedule', 'start', 'stop', 'restart', 'unschedule')]
```

After the existing `. (Join-Path $PSScriptRoot 'activity.ps1')` line add:

```powershell
. (Join-Path $PSScriptRoot 'memory.ps1')
```

- [ ] **Step 2: Add the commands** — insert into the `switch` before the `{ $_ -in 'schedule', 'restart' }` case:

```powershell
    'mem' {
        $m = Get-MemoryBreakdown
        if (-not $m) { Write-Output 'memory counters unavailable on this system' }
        else { Write-Output ("total {0} GB · in use {1} · standby cache {2} · modified {3} · free {4}" -f $m.total, $m.in_use, $m.standby, $m.modified, $m.free) }
    }

    'free' {
        $before = Get-MemoryBreakdown
        if (-not $before) { Write-Output 'memory counters unavailable on this system'; break }
        $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($admin) {
            $freed = Clear-StandbyList
        }
        else {
            try {
                Start-Process pwsh -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile', '-File', $PSCommandPath, 'free'
            }
            catch { Write-Output 'cancelled (UAC declined)'; break }
            $freed = [math]::Round([math]::Max(0, $before.standby - (Get-MemoryBreakdown).standby), 2)
        }
        $m = Get-MemoryBreakdown
        Write-Output "freed $freed GB standby cache"
        Write-Output ("now: in use {0} · standby {1} · modified {2} · free {3} GB" -f $m.in_use, $m.standby, $m.modified, $m.free)
    }
```

- [ ] **Step 3: Verify by hand** (no unit test — syscall + UAC path; spec says manual verify)

Run: `.\shipd.ps1 mem`
Expected: one line, e.g. `total 15.69 GB · in use 9.2 · standby cache 4.1 · modified 0.3 · free 2.1`

Run: `.\shipd.ps1 free` (accept the UAC prompt)
Expected: `freed <n> GB standby cache` then the `now: ...` line; `<n>` roughly matches the standby value `mem` showed. Then run again and DECLINE the UAC prompt → `cancelled (UAC declined)`.

Run: `.\test_shipd.ps1`
Expected: `all checks passed` (regression check).

- [ ] **Step 4: Commit**

```powershell
git add shipd.ps1
git commit -m "feat: shipd mem / shipd free commands (self-elevating standby purge)"
```

---

### Task 3: dashboard — MEMORY section + `f` hotkey

**Files:**
- Modify: `dashboard.ps1` — `Build-DashFrame` (params + left panel + hotkey row) and `Show-LiveDashboard` (state, per-tick fetch, key handler)
- Test: `test_shipd.ps1` (extend the frame-geometry loop)

**Interfaces:**
- Consumes: `Get-MemoryBreakdown` (Task 1); `shipd.ps1 free` elevated child (Task 2); existing `Get-Bar`, `New-Panel`, `$TH`.
- Produces: `Build-DashFrame` gains two optional params: `-Mem <pscustomobject|null>` (breakdown object) and `-MemMsg <string>` (banner, `''` = none). Existing callers without them still work.

- [ ] **Step 1: Extend the failing geometry test** — in `test_shipd.ps1`, replace the line

```powershell
    $frame = @(Build-DashFrame -Config $cfg -GitLines @('plain', "$($TH.B)colored line") -Snap $snap -Stats $stats -CpuHist @(0, 30, 100) -W $W -H $H)
```

with

```powershell
    $mem = [pscustomobject]@{ total = 16; in_use = 9.25; standby = 4.5; modified = 0.25; free = 2 }
    $frame = @(Build-DashFrame -Config $cfg -GitLines @('plain', "$($TH.B)colored line") -Snap $snap -Stats $stats -CpuHist @(0, 30, 100) -W $W -H $H -Mem $mem -MemMsg 'freed 2.5 GB')
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.\test_shipd.ps1`
Expected: FAIL — `A parameter cannot be found that matches parameter name 'Mem'`.

- [ ] **Step 3: Implement dashboard changes** — four edits in `dashboard.ps1`:

(a) `Build-DashFrame` param line becomes:

```powershell
    param($Config, [string[]]$GitLines, $Snap, $Stats, [double[]]$CpuHist, [int]$W, [int]$H, $Mem, [string]$MemMsg = '')
```

(b) In the left-panel build, right after the `foreach ($disk in $Stats.disks) { ... }` line, add:

```powershell
    if ($Mem) {
        $left += ''
        $left += "$($TH.D)MEMORY$(if ($MemMsg) { "  $($TH.B)$MemMsg" })"
        foreach ($row in @(@('use', $Mem.in_use), @('stby', $Mem.standby), @('mod', $Mem.modified), @('free', $Mem.free))) {
            $left += ('{0,-5}' -f $row[0]) + (Get-Bar ($row[1] / $Mem.total * 100) 12) + " $($TH.B)$($row[1])"
        }
    }
```

(c) The final hotkey line of `Build-DashFrame` becomes:

```powershell
    $frame + "$($TH.D)  q quit · g rescan git · f free ram$($TH.R)"
```

(d) In `Show-LiveDashboard`: after `$cpuHist = @()` add state:

```powershell
    $memMsg = ''; $memMsgTicks = 0
```

Inside the `while ($true)` loop, right after `$stats = Get-SystemStats`, add:

```powershell
            $mem = Get-MemoryBreakdown
            if ($memMsgTicks -gt 0) { $memMsgTicks-- } else { $memMsg = '' }
```

Change the `Build-DashFrame` call to pass them:

```powershell
            $frame = Build-DashFrame -Config $Config -GitLines $gitLines -Snap $snap -Stats $stats -CpuHist $cpuHist -W $W -H $H -Mem $mem -MemMsg $memMsg
```

In the key loop, after the `'g', 'G'` handler, add:

```powershell
                    if ($k.KeyChar -in 'f', 'F' -and $mem) {
                        try {
                            Start-Process pwsh -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile', '-File', "$PSScriptRoot\shipd.ps1", 'free'
                            $freed = [math]::Round([math]::Max(0, $mem.standby - (Get-MemoryBreakdown).standby), 2)
                            $memMsg = "✓ freed $freed GB"
                        }
                        catch { $memMsg = 'free ram cancelled' }   # UAC declined — not an error
                        $memMsgTicks = 5
                    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.\test_shipd.ps1`
Expected: `all checks passed` (geometry holds with the MEMORY section at all three tested sizes).

- [ ] **Step 5: Verify live by hand**

Run: `.\shipd.ps1` in a maximized terminal.
Expected: MEMORY section with 4 bars in the left panel; footer shows `f free ram`. Press `f`, accept UAC → `✓ freed X GB` appears by the MEMORY title for ~10s and the bars visibly shift (standby down, free up). Press `f` again and decline UAC → `free ram cancelled`. `q` still quits.

- [ ] **Step 6: Commit**

```powershell
git add dashboard.ps1 test_shipd.ps1
git commit -m "feat: dashboard MEMORY panel + f hotkey to free standby cache"
```

---

### Task 4: README + push

**Files:**
- Modify: `README.md` — command table + one new section

**Interfaces:** none (docs only).

- [ ] **Step 1: Update the command table** — add two rows after the `shipd snapshot` row:

```markdown
| `shipd mem` | RAM breakdown: in use / standby cache / modified / free |
| `shipd free` | Free RAM by purging the standby cache (admin prompt; also the `f` key in the dashboard) |
```

- [ ] **Step 2: Add a section** after "## Commands":

```markdown
## Freeing RAM (RAMMap-lite)

Windows keeps closed apps' data in RAM as **standby cache**, which is why Task
Manager can show 90% memory used while nothing is running. The dashboard's
MEMORY panel shows the real split, and pressing **f** (or running `shipd free`)
purges the standby cache — the same operation as Sysinternals RAMMap's
"Empty Standby List" — and shows how much was released.

This is manual-only (the background tasks never touch it) and non-destructive:
it only drops cache, never running apps' memory. The one trade-off is that the
next launch of a recently closed app may be marginally slower while Windows
re-reads it from disk. Needs one UAC click; declining it simply cancels.
```

- [ ] **Step 3: Commit and push**

```powershell
git add README.md
git commit -m "docs: memory panel + free RAM feature"
git push
```

Expected: push succeeds to https://github.com/harsh4k/shipd (pull --rebase first if the remote moved).

---

## Self-Review

- **Spec coverage:** breakdown counters → Task 1; purge + privilege → Task 1; `mem`/`free` + self-elevation → Task 2; dashboard panel, hotkey, banner, UAC-cancel handling, per-tick refresh → Task 3; localized-Windows degradation → `$null` contract in Task 1, guarded in Tasks 2 (`if (-not $before)`) and 3 (`if ($Mem)` / `-and $mem`); manual-only constraint → purge only reachable from `free`/`f`; README note → Task 4. No gaps.
- **Placeholder scan:** none — every step has literal code/commands.
- **Type consistency:** `Get-MemoryBreakdown` fields (`total, in_use, standby, modified, free`) used identically in Tasks 2, 3, and the tests; `Clear-StandbyList` returns GB double, consumed as such in Task 2.
