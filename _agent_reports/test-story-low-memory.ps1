# Monitored local game test. Stops after MaxSeconds and reports measurements.
# Hardware is the local host, not the 7900 XTX target. No pagefile change.
param(
    [string]$GameExe = 'F:\retailgame\game_scarlett_master.exe',
    [string]$VictoryExe = 'F:\VIctory-Belobug-AMD\_agent_tmp\target-low-mem-launch\diag\victory.exe',
    [string]$WorkDir = 'F:\VIctory-Belobug-AMD\_agent_tmp\low-mem-launch',
    [ValidateSet('series-x', 'series-s')][string]$Console = 'series-x',
    [ValidatePattern('^\d+x\d+$')][string]$DisplayMode = '1920x1080',
    [ValidateRange(0, 65536)][int]$BudgetMb = 256,
    [ValidateRange(0, 4096)][int]$TextureMax = 0,
    [ValidateRange(30, 3600)][int]$MaxSeconds = 600,
    [int[]]$Shots = @(30, 90, 180, 300, 480, 600),
    [string]$LogDir = 'F:\VIctory-Belobug-AMD\_agent_reports\logs'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path -LiteralPath $VictoryExe)) { throw "No $VictoryExe; build it first." }
if (-not (Test-Path -LiteralPath $GameExe)) { throw "No $GameExe" }
if (-not (Test-Path -LiteralPath $WorkDir)) { throw "No $WorkDir" }
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

Add-Type @'
using System;
using System.Runtime.InteropServices;
public struct MEMORYSTATUSEX_TEST {
    public uint dwLength; public uint dwMemoryLoad;
    public ulong ullTotalPhys; public ulong ullAvailPhys;
    public ulong ullTotalPageFile; public ulong ullAvailPageFile;
    public ulong ullTotalVirtual; public ulong ullAvailVirtual;
    public ulong ullAvailExtendedVirtual;
}
public static class MemStatTest {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX_TEST value);
}
'@

$GameExe = (Resolve-Path -LiteralPath $GameExe).Path
$VictoryExe = (Resolve-Path -LiteralPath $VictoryExe).Path

$paths = 'VICTORY_CONFIG', 'VICTORY_GAME_DIR', 'VICTORY_CACHE_DIR', 'VICTORY_DATA_DIR'
Get-ChildItem Env:VICTORY_* | Where-Object { $_.Name -notin $paths } | ForEach-Object {
    Remove-Item "Env:$($_.Name)"
}
$env:VICTORY_GAME_DIR = 'F:\retailgame'
$env:VICTORY_CACHE_DIR = 'F:\victory-cache-retail'
$env:VICTORY_DATA_DIR = 'F:\victory-data-retail'

$settings = @{
    VICTORY_TEXTURE_NO_WAIT   = '1'
    VICTORY_RELAY             = '2'
    VICTORY_WIDE_BACK         = '1'
    VICTORY_CARD_REHASH_RUNS  = '1'
    VICTORY_JOIN_COPIES       = '1'
    VICTORY_INDIRECT_WINDOW   = '1'
    VICTORY_RELAY_COPY        = '1'
    VICTORY_CARD_STEPS        = '2'
    VICTORY_INDIRECT_BATCH    = '2'
    VICTORY_MAP_THREADS       = '1'
    VICTORY_TITLE_PRIORITIES  = '0'
    VICTORY_CARD_AWAKE        = '1'
    VICTORY_SHOW_AFTER        = '1'
    VICTORY_AMBIENT           = '0.8'
    VICTORY_D3D12_DRED        = 'light'
    VICTORY_SKIP_PIPELINES    = 'none'
    VICTORY_UNDER_WIDE        = '0'
    VICTORY_LAND_ECHO         = '0'
    VICTORY_MEMORY_LOG_SECS   = '2'
    VICTORY_LAZY_PHYSICAL     = '1'
    VICTORY_FILE_PHYSICAL     = '1'
    VICTORY_TEXTURE_MAX       = [string]$TextureMax
    VICTORY_DISPLAY_MODE      = $DisplayMode
    VICTORY_WINDOW_BUDGET_MB  = [string]$BudgetMb
    VICTORY_LOG               = 'victory_gpu::frame=debug,victory::memory=info,info'
}
foreach ($k in $settings.Keys) { Set-Item "Env:$k" $settings[$k] }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $LogDir "test-story-$Console-$stamp.out"
$err = Join-Path $LogDir "test-story-$Console-$stamp.err"
$csv = Join-Path $LogDir "test-story-$Console-$stamp.samples.csv"
$summary = Join-Path $LogDir "test-story-$Console-$stamp.summary.txt"
$shotDir = Join-Path $LogDir "test-story-$Console-$stamp-shots"
New-Item -ItemType Directory -Path $shotDir | Out-Null

$argsList = @('run', '--console', $Console, "`"$GameExe`"", '--execute')
$p = Start-Process -FilePath $VictoryExe -ArgumentList $argsList -WorkingDirectory $WorkDir `
    -RedirectStandardOutput $out -RedirectStandardError $err -PassThru

$header = @(
    'hardware=RX 6950 XT / Ryzen 5 3600 / 32 GB / Windows 11',
    "victory=$VictoryExe", "game=$GameExe", "console=$Console",
    "display=$DisplayMode", "window_budget_mb=$BudgetMb", "max_seconds=$MaxSeconds",
    "pid=$($p.Id)", 'pagefile=unchanged'
) + ($settings.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" })
$header | Out-File -LiteralPath $summary -Encoding utf8
"seconds,private_mb,working_mb,free_phys_mb,commit_headroom_mb" | Out-File -LiteralPath $csv -Encoding ascii

function Sample-Brightness($seconds) {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $path = Join-Path $shotDir ("frame-{0:D4}s.png" -f $seconds)
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $sum = 0.0; $n = 0; $min = 255; $max = 0
        for ($y = 0; $y -lt $bounds.Height; $y += 16) {
            for ($x = 0; $x -lt $bounds.Width; $x += 16) {
                $c = $bmp.GetPixel($x, $y)
                $v = [int](([int]$c.R + [int]$c.G + [int]$c.B) / 3)
                $sum += $v; $n++
                if ($v -lt $min) { $min = $v }
                if ($v -gt $max) { $max = $v }
            }
        }
        return ("shot_{0}s.png avg={1:N1} min={2} max={3}" -f $seconds, ($sum / $n), $min, $max)
    } finally {
        $g.Dispose(); $bmp.Dispose()
    }
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$nextShot = @($Shots | Sort-Object)
$stopReason = 'timeout'
while ($true) {
    Start-Sleep -Milliseconds 900
    $p.Refresh()
    $secs = [int]$sw.Elapsed.TotalSeconds
    $m = New-Object MEMORYSTATUSEX_TEST
    $m.dwLength = [System.Runtime.InteropServices.Marshal]::SizeOf([type]'MEMORYSTATUSEX_TEST')
    $privateMb = -1; $workingMb = -1
    if (-not $p.HasExited) {
        try {
            $proc = Get-Process -Id $p.Id -ErrorAction Stop
            $privateMb = [int]($proc.PrivateMemorySize64 / 1MB)
            $workingMb = [int]($proc.WorkingSet64 / 1MB)
        } catch {}
    }
    if (-not [MemStatTest]::GlobalMemoryStatusEx([ref]$m)) {
        $m.ullAvailPhys = 0
        $m.ullAvailPageFile = 0
    }
    $freeMb = [int]($m.ullAvailPhys / 1MB)
    $commitMb = [int]($m.ullAvailPageFile / 1MB)
    "{0},{1},{2},{3},{4}" -f $secs, $privateMb, $workingMb, $freeMb, $commitMb |
        Out-File -LiteralPath $csv -Append -Encoding ascii

    while ($nextShot.Count -gt 0 -and $secs -ge $nextShot[0]) {
        $at = $nextShot[0]
        $nextShot = @($nextShot | Select-Object -Skip 1)
        if (-not $p.HasExited) {
            $line = Sample-Brightness $at
            $line | Out-File -LiteralPath $summary -Append -Encoding utf8
        }
    }

    if ($p.HasExited) {
        $stopReason = "exited exit_code=$($p.ExitCode)"
        break
    }
    if ($secs -ge $MaxSeconds) {
        $stopReason = "timeout_killed"
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        break
    }
}

$elapsed = [int]$sw.Elapsed.TotalSeconds
"elapsed_s=$elapsed stop=$stopReason" | Out-File -LiteralPath $summary -Append -Encoding utf8
"stdout=$out" | Out-File -LiteralPath $summary -Append -Encoding utf8
"stderr=$err" | Out-File -LiteralPath $summary -Append -Encoding utf8
"samples=$csv" | Out-File -LiteralPath $summary -Append -Encoding utf8
"shots=$shotDir" | Out-File -LiteralPath $summary -Append -Encoding utf8

if (Test-Path -LiteralPath $err) {
    $intervals = [System.Collections.Generic.List[double]]::new()
    $maxFrame = 0
    $framePresented = 0
    $worldMarkers = [System.Collections.Generic.List[string]]::new()
    foreach ($line in (Get-Content -LiteralPath $err -Encoding UTF8)) {
        # Normalize ANSI/ESC sequences; tracing may colorize fields/values.
        $clean = [regex]::Replace($line, '\x1b\[[0-9;]*[A-Za-z]', '')
        $clean = [regex]::Replace($clean, '\x1b', '')

        # Diagnostics frame interval log: "victory_gpu::frame ... frame=<n> interval_us=<us> ... frame interval"
        if ($clean -match 'interval_us\D*?(\d+)') {
            $intervals.Add([double]$Matches[1] / 1000.0)
            $framePresented++
            if ($clean -match '\bframe(?:=|\s+)\D*?(\d+)') { $maxFrame = [math]::Max($maxFrame, [int]$Matches[1]) }
            continue
        }

        # Legacy/fallback presented-frame markers.
        if ($clean -match 'frame presented|presented frame') {
            $framePresented++
            if ($clean -match '\bframe(?:=|\s+)\D*?(\d+)') { $maxFrame = [math]::Max($maxFrame, [int]$Matches[1]) }
        }
        if ($clean -match 'mission|world loaded|loading screen|story|cutscene|gameplay|level loaded') {
            if ($worldMarkers.Count -lt 40) { $worldMarkers.Add($clean.Trim()) }
        }
    }
    $intervalArr = @($intervals | Sort-Object)
    function Percentile([double[]]$values, [double]$p) {
        if ($values.Count -eq 0) { return $null }
        $rank = [math]::Ceiling($p / 100.0 * $values.Count) - 1
        $rank = [math]::Max(0, [math]::Min($rank, $values.Count - 1))
        return $values[$rank]
    }
    $brightness = @()
    foreach ($s in (Get-Content -LiteralPath $summary -ErrorAction SilentlyContinue)) {
        if ($s -match '^shot_\d+s\.png avg=(?<avg>[0-9,\.]+) min=(?<min>\d+) max=(?<max>\d+)') {
            $brightness += [pscustomobject]@{ avg=[double]($Matches['avg'] -replace ',','.'); min=[int]$Matches['min']; max=[int]$Matches['max'] }
        }
    }
    $worldEntryCandidate = $false
    $worldEntryReason = 'no'
    # Heuristic only: sustained present cadence + non-black screenshots. Never proof.
    $nonBlack = $false
    $maxAvg = $null; $maxMax = $null
    if ($brightness.Count -gt 0) {
        $maxAvg = ($brightness | Measure-Object avg -Maximum).Maximum
        $maxMax = ($brightness | Measure-Object max -Maximum).Maximum
        $nonBlack = ($maxAvg -ge 2.0 -or $maxMax -ge 16)
    }
    $sustained = ($framePresented -ge 100 -and $intervalArr.Count -ge 100)
    if ($sustained -and $nonBlack) {
        $worldEntryCandidate = $true
        $worldEntryReason = 'heuristic_sustained_present_and_nonblack_screenshots'
    } elseif ($sustained -and $brightness.Count -gt 0 -and -not $nonBlack) {
        $worldEntryReason = 'heuristic_rejected_screenshots_near_black'
    } elseif ($sustained) {
        $worldEntryReason = 'heuristic_sustained_present_no_screenshot_signal'
    } elseif ($framePresented -gt 0 -or $intervalArr.Count -gt 0) {
        $worldEntryReason = 'insufficient_present_samples'
    }
    $statLines = @(
        "frame_interval_count=$($intervalArr.Count)",
        "max_frame_logged=$maxFrame",
        "frame_presented_log_count=$framePresented",
        "world_entry_candidate=$worldEntryCandidate",
        "world_entry_reason=$worldEntryReason"
    )
    if ($intervalArr.Count -gt 0) {
        $statLines += @(
            ("frame_ms_median={0:N2}" -f (Percentile $intervalArr 50)),
            ("frame_ms_p95={0:N2}" -f (Percentile $intervalArr 95)),
            ("frame_ms_p99={0:N2}" -f (Percentile $intervalArr 99)),
            ("frame_ms_longest={0:N2}" -f $intervalArr[$intervalArr.Count - 1])
        )
    }
    if ($worldMarkers.Count -gt 0) {
        $statLines += "--- world/load markers (heuristic, not proof) ---"
        $statLines += @($worldMarkers)
    }
    $statLines | Out-File -LiteralPath $summary -Append -Encoding utf8
}

$failures = @()
if (Test-Path -LiteralPath $err) {
    $failures = @(Select-String -LiteralPath $err -Pattern '0x8007000E|memory allocation of|no host texture|no upload buffer|no host list for a state prelude|VIctory: host GPU failure|idle title-memory windows given back' | ForEach-Object {
        $clean = [regex]::Replace($_.Line, "`e`[[0-9;]*m", '')
        $clean
    } | Select-Object -Last 40)
}
if ($failures.Count -gt 0) {
    "--- notable log lines ---" | Out-File -LiteralPath $summary -Append -Encoding utf8
    $failures | Out-File -LiteralPath $summary -Append -Encoding utf8
}

Write-Host "summary=$summary"
Get-Content -LiteralPath $summary -Tail 30


