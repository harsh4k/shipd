# Activity snapshot: processes (Get-Process), focused app + idle time (Win32 via P/Invoke).

Add-Type -Namespace Win32 -Name User32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
[StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
[DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
'@

function Get-IdleSeconds {
    $lii = New-Object 'Win32.User32+LASTINPUTINFO'
    $lii.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($lii)
    [void][Win32.User32]::GetLastInputInfo([ref]$lii)
    # TickCount is a wrapping 32-bit counter; mask math survives the wrap
    $now = [int64][Environment]::TickCount -band 0xFFFFFFFF
    [math]::Round((($now - $lii.dwTime) -band 0xFFFFFFFF) / 1000, 1)
}

function Get-FocusedProcessName {
    $hwnd = [Win32.User32]::GetForegroundWindow()
    $procId = [uint]0
    [void][Win32.User32]::GetWindowThreadProcessId($hwnd, [ref]$procId)
    if ($procId) { (Get-Process -Id $procId -ErrorAction SilentlyContinue).ProcessName }
}

# Own stats, PS-native (no psutil/python): CIM for CPU/RAM/disk, nvidia-smi or perf counters for GPU.
function Get-SystemStats {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
    if ($null -eq $cpu) {
        try { $cpu = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples[0].CookedValue } catch { $cpu = -1 }
    }
    $disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
        '{0} {1}/{2} GB' -f $_.DeviceID, [math]::Round(($_.Size - $_.FreeSpace) / 1GB, 1), [math]::Round($_.Size / 1GB, 1)
    })
    $gpu = 'N/A'
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        $q = nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1
        if ($q) { $p = $q -split ',\s*'; $gpu = "$($p[0])% $($p[1])C" }
    }
    if ($gpu -eq 'N/A') {
        # works for any GPU vendor on Win10+; counter name is localized, so try/catch
        try {
            $sum = ((Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage').CounterSamples |
                Measure-Object CookedValue -Sum).Sum
            $gpu = "$([math]::Round($sum))%"
        } catch {}
    }
    [pscustomobject]@{
        cpu       = [math]::Round($cpu)
        gpu       = $gpu
        ram_used  = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
        ram_total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        disks     = $disks
    }
}

function Get-ActivitySnapshot {
    param($Config)
    $procs = @(Get-Process | Select-Object -ExpandProperty ProcessName -Unique | Sort-Object)
    $games = @($Config.known_games | ForEach-Object { $_ -replace '\.exe$', '' })
    [pscustomobject]@{
        timestamp     = (Get-Date).ToString('s')
        focused       = Get-FocusedProcessName
        idle_seconds  = Get-IdleSeconds
        games_running = @($procs | Where-Object { $games -contains $_ })
    }
}
