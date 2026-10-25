#requires -Version 7.2
<#
Windows/local Godot checks. Import the checkout once before running checks.
  ./tests/run_tests.ps1
  ./tests/run_tests.ps1 -Check run_checks -Rendered
  ./tests/run_tests.ps1 -List
GODOT_EXE or -Godot supplies the executable. Logs/user data remain below builds/test-runs by default.
#>
[CmdletBinding()]
param(
    [ValidateSet('quick')][string]$Suite = 'quick',
    [string[]]$Check,
    [string[]]$Arguments = @(),
    [string]$Godot = $env:GODOT_EXE,
    [string]$OutputRoot,
    [ValidateRange(1, 1800)][int]$TimeoutSeconds = 120,
    [ValidateRange(1, 600)][int]$LockWaitSeconds = 120,
    [ValidatePattern('^\d+x\d+$')][string]$Resolution = '1920x1080',
    [switch]$Rendered,
    [switch]$Audible,
    [switch]$List
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$suites = @{
    quick = @('run_checks')
}
# Deliberately explicit opt-in checks; this is not filesystem discovery.
$extra = @()
$allowed = @($suites.quick + $extra | Select-Object -Unique)
if ($List) {
    foreach ($name in $suites.Keys) { Write-Host "$name`: $($suites[$name] -join ', ')" }
    Write-Host "Direct checks: $($extra -join ', ')"
    return
}
if (-not $IsWindows) { throw 'This local launcher uses Windows job objects; invoke Godot directly on other platforms.' }
$selected = if ($Check) { @($Check | Select-Object -Unique) } else { $suites[$Suite] }
foreach ($name in $selected) { if ($name -notin $allowed) { throw "Unknown check '$name'; use -List." } }
if (-not $Godot) {
    $default = 'C:/Users/Home/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe'
    $Godot = if (Test-Path -LiteralPath $default) { $default } else { (Get-Command godot -CommandType Application -ErrorAction SilentlyContinue).Source }
}
if (-not $Godot) { throw 'Supply -Godot <executable> or set GODOT_EXE.' }
$Godot = (Get-Command $Godot -CommandType Application).Source
# The console stub spawns the real engine before we could assign its job. Launch the engine itself.
if ($Godot.EndsWith('_console.exe', [StringComparison]::OrdinalIgnoreCase)) {
    $engine = $Godot.Substring(0, $Godot.Length - '_console.exe'.Length) + '.exe'
    if (-not (Test-Path -LiteralPath $engine)) { throw "Console launcher requires its sibling engine: $engine" }
    $Godot = $engine
}
if (-not $OutputRoot) { $OutputRoot = Join-Path $repo 'builds/test-runs' }
# Keep run output out of the editor's resource scan.
foreach ($ignored in @((Join-Path $repo 'builds'), [IO.Path]::GetFullPath($OutputRoot))) {
    [IO.Directory]::CreateDirectory($ignored) | Out-Null
    $marker = Join-Path $ignored '.gdignore'
    if (-not (Test-Path -LiteralPath $marker)) { [IO.File]::WriteAllText($marker, '') }
}
$run = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) ('{0}-{1}-{2}' -f [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'), $PID, [Guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($run) | Out-Null
$lockRoot = Join-Path ([IO.Path]::GetTempPath()) 'plaag-godot-test-slots'
[IO.Directory]::CreateDirectory($lockRoot) | Out-Null

# Native lifetime containment: closing the handle (including launcher death) kills descendants.
if (-not ('PlaagTestJob' -as [type])) {
    Add-Type @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public sealed class PlaagTestJob : IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct Basic {
        public long ProcessTime, JobTime; public uint Flags;
        public UIntPtr MinWorking, MaxWorking; public uint Active;
        public UIntPtr Affinity; public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] struct Io { public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }
    [StructLayout(LayoutKind.Sequential)] struct Limits { public Basic Basic; public Io Io; public UIntPtr ProcessMemory, JobMemory, PeakProcess, PeakJob; }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr security, string name);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int info, ref Limits limits, uint length);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    IntPtr handle;
    public PlaagTestJob() {
        handle = CreateJobObject(IntPtr.Zero, null);
        var limits = new Limits(); limits.Basic.Flags = 0x2000; // KILL_ON_JOB_CLOSE
        if (handle == IntPtr.Zero || !SetInformationJobObject(handle, 9, ref limits, (uint)Marshal.SizeOf(limits))) {
            int error = Marshal.GetLastWin32Error(); Dispose(); throw new Win32Exception(error);
        }
    }
    public void Add(IntPtr process) { if (!AssignProcessToJobObject(handle, process)) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    public void Dispose() { if (handle != IntPtr.Zero) { CloseHandle(handle); handle = IntPtr.Zero; } }
}
'@
}

function Open-TestSlots([int]$count) {
    $held = @()
    $wait = [Diagnostics.Stopwatch]::StartNew()
    try {
        while ($held.Count -lt $count) {
            foreach ($slot in 0..1) {
                if ($held | Where-Object { $_.Name -eq (Join-Path $lockRoot "$slot.lock") }) { continue }
                # A two-slot check acquires in order; competing exclusive checks cannot deadlock.
                if ($count -eq 2 -and $slot -ne $held.Count) { continue }
                try { $held += [IO.File]::Open((Join-Path $lockRoot "$slot.lock"), 'OpenOrCreate', 'ReadWrite', 'None') }
                catch [IO.IOException] { }
                if ($held.Count -eq $count) { break }
            }
            if ($held.Count -eq $count) { return $held }
            if ($wait.Elapsed.TotalSeconds -ge $LockWaitSeconds) { throw "Timed out waiting for $count Godot slot(s)." }
            Start-Sleep -Milliseconds 100
        }
    } catch { foreach ($handle in $held) { $handle.Dispose() }; throw }
}

$failed = 0
$summary = Join-Path $run 'summary.txt'
Write-Host "Logs and isolated user data: $run"
foreach ($name in $selected) {
    $folder = Join-Path $run $name
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    $rendered = [bool]$Rendered
    if ($Audible -and -not $rendered) { throw '-Audible requires -Rendered.' }
    # Rendered runs take both slots, so they never share the machine.
    $slots = if ($rendered) { 2 } else { 1 }
    $held = @(); $job = $null; $process = $null
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $reason = ''; $stdout = $null; $stderr = $null; $outText = ''; $errText = ''
    try {
        $held = @(Open-TestSlots $slots)
        $job = [PlaagTestJob]::new()
        $start = [Diagnostics.ProcessStartInfo]::new($Godot)
        $start.WorkingDirectory = $repo
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.Environment['APPDATA'] = Join-Path $folder 'appdata'
        $start.Environment['LOCALAPPDATA'] = Join-Path $folder 'localappdata'
        $start.Environment['XDG_DATA_HOME'] = Join-Path $folder 'xdg-data'
        $start.Environment['XDG_CONFIG_HOME'] = Join-Path $folder 'xdg-config'
        $start.Environment['XDG_CACHE_HOME'] = Join-Path $folder 'xdg-cache'
        $start.Environment['PLAAG_TEST_ROOT'] = $folder
        $engineArgs = @('--log-file', (Join-Path $folder 'godot.log'), '--script', "res://tests/$name.gd", '--path', $repo)
        if (-not $Audible) { $engineArgs += @('--audio-driver', 'Dummy') }
        if (-not $rendered) { $engineArgs += '--headless' }
        else { $engineArgs += @('--resolution', $Resolution, '--windowed') }
        foreach ($arg in @($engineArgs + @('--') + $Arguments)) { $start.ArgumentList.Add($arg) }
        $process = [Diagnostics.Process]::Start($start)
        $job.Add($process.Handle)
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $execution = [Diagnostics.Stopwatch]::StartNew()
        while (-not $process.WaitForExit(100)) {
            if ($execution.Elapsed.TotalSeconds -ge $TimeoutSeconds) { throw "Execution timed out after $TimeoutSeconds seconds." }
        }
        if ($process.ExitCode -ne 0) { $reason = "exit $($process.ExitCode)" }
    } catch { $reason = $_.Exception.Message }
    finally {
        try {
            if ($job) { $job.Dispose() }
            if ($process -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit(5000) | Out-Null }
            if ($stdout) { $outText = if ($stdout.Wait(5000)) { $stdout.GetAwaiter().GetResult() } else { throw 'Output capture timed out.' } }
            if ($stderr) { $errText = if ($stderr.Wait(5000)) { $stderr.GetAwaiter().GetResult() } else { throw 'Error capture timed out.' } }
        } catch { if (-not $reason) { $reason = $_.Exception.Message } }
        finally {
            if ($process) { $process.Dispose() }
            foreach ($handle in $held) { $handle.Dispose() }
        }
        [IO.File]::WriteAllText((Join-Path $folder 'stdout.log'), $outText)
        [IO.File]::WriteAllText((Join-Path $folder 'stderr.log'), $errText)
    }
    # The engine log can miss teardown output; scan the raw streams too, without double counting.
    $warnings = 0
    $seenLines = @{}
    foreach ($log in @('godot.log', 'stdout.log', 'stderr.log')) {
        $path = Join-Path $folder $log
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $raw = $log -ne 'godot.log'
        foreach ($line in @(Get-Content -LiteralPath $path)) {
            if ($line -notmatch '^(ERROR:|SCRIPT ERROR:|WARNING:)' -and $line -notmatch 'Parse Error:') { continue }
            if ($raw -and $seenLines[$line] -gt 0) { $seenLines[$line]--; continue }
            if (-not $raw) { $seenLines[$line] = 1 + $seenLines[$line] }
            if ($line -match '^WARNING:') { $warnings++; continue }
            if (-not $reason) { $reason = "Unexpected Godot error: $line" }
        }
    }
    $status = if ($reason) { 'FAIL' } else { 'PASS' }
    $line = '{0} {1} {2:F2}s {3}' -f $status, $name, $watch.Elapsed.TotalSeconds, $reason
    if ($warnings) { $line += " [warnings: $warnings]" }
    Write-Host $line
    [IO.File]::AppendAllText($summary, "$line`n")
    if ($reason) { $failed++; Write-Host "  Full logs: $folder"; break }
}
exit ([int]($failed -gt 0))
