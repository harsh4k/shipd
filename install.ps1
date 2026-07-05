# shipd one-line installer:  irm https://raw.githubusercontent.com/harsh4k/shipd/master/install.ps1 | iex
# Runs in Windows PowerShell 5.1 or pwsh 7 (so it must stay 5.1-compatible: no &&, no ternary).
# Re-running it updates the code but keeps config.json, snapshots and reports.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ── 1. shipd itself needs PowerShell 7 ($PSStyle) ──
$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwsh) { $pwsh = $pwsh.Source }
else {
    $p7 = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (Test-Path $p7) { $pwsh = $p7 }
    else {
        $ans = Read-Host 'shipd needs PowerShell 7. Install it now via winget? (y/n)'
        if ($ans -notmatch '^[yY]') { Write-Host 'cancelled - get PowerShell 7 from https://aka.ms/powershell and re-run'; return }
        winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements
        if (Test-Path $p7) { $pwsh = $p7 }
        else { Write-Host 'pwsh not visible yet - open a NEW terminal and re-run the install line'; return }
    }
}

# ── 2. download + extract to %LOCALAPPDATA%\shipd ──
$dest = Join-Path $env:LOCALAPPDATA 'shipd'
$tmp = Join-Path $env:TEMP "shipd_install_$(Get-Random)"
New-Item -ItemType Directory -Force $tmp | Out-Null
Write-Host 'downloading shipd...'
Invoke-WebRequest 'https://github.com/harsh4k/shipd/archive/refs/heads/master.zip' -OutFile "$tmp\shipd.zip" -UseBasicParsing
Expand-Archive "$tmp\shipd.zip" $tmp -Force
New-Item -ItemType Directory -Force $dest | Out-Null
$hadConfig = Test-Path "$dest\config.json"   # update: keep the user's config
Get-ChildItem "$tmp\shipd-master" | Where-Object { -not ($hadConfig -and $_.Name -eq 'config.json') } |
    Copy-Item -Destination $dest -Recurse -Force
Remove-Item -Recurse -Force $tmp

# ── 2b. Generate CMD wrapper ──
$cmdContent = @"
@echo off
`"$pwsh`" -NoProfile -File "%LOCALAPPDATA%\shipd\shipd.ps1" %*
"@
$cmdPath = Join-Path $dest 'shipd.cmd'
Set-Content -Path $cmdPath -Value $cmdContent -Force

Get-ChildItem $dest -Recurse -File | Unblock-File   # drop mark-of-the-web so RemoteSigned policy runs it

# ── 3. fresh install: point the GIT panel at their projects ──
if (-not $hadConfig) {
    $default = Join-Path $HOME 'Projects'
    if (-not (Test-Path $default)) { $default = $HOME }
    $roots = $env:SHIPD_ROOTS   # non-interactive override (used by tests)
    if (-not $roots) { $roots = Read-Host "folder that holds your git projects [$default]" }
    if (-not $roots) { $roots = $default }
    $cfg = Get-Content "$dest\config.json" -Raw | ConvertFrom-Json
    $cfg.git_roots = @($roots)
    $cfg | ConvertTo-Json | Set-Content "$dest\config.json"
}

# ── 4. 'shipd' command (pwsh profile) + background tasks ──
& $pwsh -NoProfile -File "$dest\shipd.ps1" install
& $pwsh -NoProfile -File "$dest\shipd.ps1" schedule

# ── 5. make 'shipd' work from Windows PowerShell 5.1 windows too ──
$ps5profile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\profile.ps1'
if (-not (Test-Path $ps5profile)) { New-Item -ItemType File -Force $ps5profile | Out-Null }
if ("$(Get-Content $ps5profile -Raw)" -notmatch 'function shipd') {   # "$()": empty file gives $null, and $null -notmatch returns @() (falsy)
    Add-Content $ps5profile "`nfunction shipd { & `"$pwsh`" -NoProfile -File `"$dest\shipd.ps1`" @args }"
}

# ── 6. add %LOCALAPPDATA%\shipd to User PATH if not present ──
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathEntries = @()
if ($userPath) {
    $pathEntries = @($userPath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
$found = $false
foreach ($entry in $pathEntries) {
    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($entry)
        if ($expanded -eq $dest -or $entry -eq $dest -or $entry -eq '%LOCALAPPDATA%\shipd') {
            $found = $true
            break
        }
    } catch {}
}
if (-not $found) {
    $newPath = ($pathEntries + '%LOCALAPPDATA%\shipd') -join ';'
    Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value $newPath -Type ExpandString
    Write-Host "Added %LOCALAPPDATA%\shipd to persistent User PATH"
    
    # Broadcast environment change so new terminals pick it up instantly without logging off/rebooting
    try {
        $sig = '[DllImport("user32.dll",SetLastError=true,CharSet=CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);'
        $win32 = Add-Type -MemberDefinition $sig -Name "Win32SendMessage" -Namespace "Win32" -PassThru -ErrorAction SilentlyContinue
        if ($win32) {
            $result = [IntPtr]::Zero
            [void]$win32::SendMessageTimeout([IntPtr]0xffff, 0x001A, [IntPtr]::Zero, "Environment", 2, 5000, [ref]$result)
        }
    } catch {}
}

# Update current process PATH
$processPathEntries = @($env:PATH -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$foundProcess = $false
foreach ($entry in $processPathEntries) {
    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($entry)
        if ($expanded -eq $dest -or $entry -eq $dest) {
            $foundProcess = $true
            break
        }
    } catch {}
}
if (-not $foundProcess) {
    $newProcessPath = ($processPathEntries + $dest) -join ';'
    $env:PATH = $newProcessPath
    Write-Host "Updated current process PATH"
}

Write-Host ''
# ── 7. helper for CMD that is already open ──
$batPath = Join-Path $dest 'refresh_shipd_path.bat'
$batContent = '@echo off && set "PATH=%PATH%;%LOCALAPPDATA%\\shipd" && echo PATH refreshed for this CMD session'
Set-Content -Path $batPath -Value $batContent -Encoding ASCII -Force

Write-Host "If you have a CMD window already open, run: refresh_shipd_path"
Write-Host 'shipd installed - open a NEW terminal and type: shipd'
