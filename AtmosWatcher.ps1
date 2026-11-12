$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $scriptRoot "Config.ps1")

$config = Get-AtmosConfig -Path (Join-Path $scriptRoot "config.txt")

$stateDirectory = Join-Path $env:LOCALAPPDATA "AtmosAutomation"
$logPath = Join-Path $stateDirectory "automation.log"

New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null

$hashInput = $config.WindowsDeviceId + "|" + $config.AudioDevice
$sha = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($hashInput))
$deviceHash = ([BitConverter]::ToString($hashBytes)).Replace("-", "").Substring(0, 16)

$backupPath = Join-Path $stateDirectory "original-format-$deviceHash.dat"

$script:CurrentProfile = $null
$sourcePrefix = "AtmosAutomation"

function Write-Log {
    param([string]$Message)

    $line = "{0}  {1}{2}" -f (
        Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ), $Message, [Environment]::NewLine

    try {
        [System.IO.File]::AppendAllText(
            $logPath,
            $line,
            [System.Text.Encoding]::UTF8
        )
    }
    catch {
        # Logging failures must not stop the watcher.
    }
}

function Invoke-SVV {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & $config.SoundVolumeViewPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "SoundVolumeView failed with exit code $exitCode. $($output -join ' ')"
    }
}

function Save-OriginalFormat {
    if (Test-Path -LiteralPath $backupPath) {
        return
    }

    Invoke-SVV -Arguments @(
        "/SaveDeviceFormat",
        $config.AudioDevice,
        $backupPath
    )

    if (-not (Test-Path -LiteralPath $backupPath)) {
        throw "Failed to save the original audio format."
    }

    Write-Log "Original audio format saved."
}

function Set-MusicProfile {
    param([switch]$Force)

    if ($script:CurrentProfile -eq "Music" -and -not $Force) {
        return
    }

    Save-OriginalFormat

    Invoke-SVV -Arguments @(
        "/SetDefaultFormat",
        $config.AudioDevice,
        [string]$config.MusicBitDepth,
        [string]$config.MusicSampleRate
    )

    Invoke-SVV -Arguments @(
        "/SetSpatial",
        $config.AudioDevice,
        ""
    )

    $script:CurrentProfile = "Music"

    Write-Log "Music profile activated: $($config.MusicBitDepth)-bit / $($config.MusicSampleRate) Hz. Spatial Sound disabled."
}

function Set-AtmosProfile {
    param([switch]$Force)

    if ($script:CurrentProfile -eq "Atmos" -and -not $Force) {
        return
    }

    if (Test-Path -LiteralPath $backupPath) {
        Invoke-SVV -Arguments @(
            "/LoadDeviceFormat",
            $config.AudioDevice,
            $backupPath
        )
    }

    Invoke-SVV -Arguments @(
        "/SetSpatial",
        $config.AudioDevice,
        $config.AtmosGuid
    )

    $script:CurrentProfile = "Atmos"

    Write-Log "Dolby Atmos for Home Theater profile activated."
}

function Test-TargetProcessRunning {
    foreach ($processFile in $config.TargetProcesses) {
        $processName = [System.IO.Path]::GetFileNameWithoutExtension($processFile)

        if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
            return $true
        }
    }

    return $false
}

function Apply-CurrentProfile {
    param([switch]$Force)

    if (Test-TargetProcessRunning) {
        Set-MusicProfile -Force:$Force
    }
    else {
        Set-AtmosProfile -Force:$Force
    }
}

# Core Audio default playback device notification interface.
if (-not ("AtmosCoreAudioWatcher" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[ComImport]
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator
{
    int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IntPtr device);
    int GetDevice(string id, out IntPtr device);
    int RegisterEndpointNotificationCallback(IMMNotificationClient client);
    int UnregisterEndpointNotificationCallback(IMMNotificationClient client);
}

[ComImport]
[Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
class MMDeviceEnumeratorComObject
{
}

[Guid("7991EEC9-7E89-4D85-8390-6C703CEC60C0")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMNotificationClient
{
    int OnDeviceStateChanged(
        [MarshalAs(UnmanagedType.LPWStr)] string id,
        int state
    );

    int OnDeviceAdded(
        [MarshalAs(UnmanagedType.LPWStr)] string id
    );

    int OnDeviceRemoved(
        [MarshalAs(UnmanagedType.LPWStr)] string id
    );

    int OnDefaultDeviceChanged(
        int flow,
        int role,
        [MarshalAs(UnmanagedType.LPWStr)] string id
    );

    int OnPropertyValueChanged(
        [MarshalAs(UnmanagedType.LPWStr)] string id,
        IntPtr key
    );
}

public class AtmosDefaultDeviceEventArgs : EventArgs
{
    public string DeviceId { get; private set; }
    public int Flow { get; private set; }
    public int Role { get; private set; }

    public AtmosDefaultDeviceEventArgs(string id, int flow, int role)
    {
        DeviceId = id;
        Flow = flow;
        Role = role;
    }
}

[ClassInterface(ClassInterfaceType.None)]
public class AtmosCoreAudioWatcher : IMMNotificationClient
{
    private IMMDeviceEnumerator enumerator;

    public event EventHandler<AtmosDefaultDeviceEventArgs> DefaultDeviceChanged;

    public AtmosCoreAudioWatcher()
    {
        enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();

        Marshal.ThrowExceptionForHR(
            enumerator.RegisterEndpointNotificationCallback(this)
        );
    }

    public int OnDeviceStateChanged(string id, int state) { return 0; }
    public int OnDeviceAdded(string id) { return 0; }
    public int OnDeviceRemoved(string id) { return 0; }
    public int OnPropertyValueChanged(string id, IntPtr key) { return 0; }

    public int OnDefaultDeviceChanged(int flow, int role, string id)
    {
        var handler = DefaultDeviceChanged;

        if (handler != null)
        {
            handler(
                this,
                new AtmosDefaultDeviceEventArgs(id, flow, role)
            );
        }

        return 0;
    }

    public void Dispose()
    {
        if (enumerator != null)
        {
            enumerator.UnregisterEndpointNotificationCallback(this);
            Marshal.ReleaseComObject(enumerator);
            enumerator = null;
        }
    }
}
'@
}

$audioWatcher = $null

try {
    $audioWatcher = New-Object AtmosCoreAudioWatcher

    Register-ObjectEvent `
        -InputObject $audioWatcher `
        -EventName DefaultDeviceChanged `
        -SourceIdentifier "$sourcePrefix.DefaultDeviceChanged" |
        Out-Null

    $index = 0

    foreach ($processFile in $config.TargetProcesses) {
        $escapedName = $processFile.Replace("'", "''")

        $startQuery = "SELECT * FROM Win32_ProcessStartTrace WHERE ProcessName = '$escapedName'"
        $stopQuery = "SELECT * FROM Win32_ProcessStopTrace WHERE ProcessName = '$escapedName'"

        Register-WmiEvent `
            -Query $startQuery `
            -SourceIdentifier "$sourcePrefix.ProcessStart.$index" |
            Out-Null

        Register-WmiEvent `
            -Query $stopQuery `
            -SourceIdentifier "$sourcePrefix.ProcessStop.$index" |
            Out-Null

        $index++
    }

    Write-Log "AtmosWatcher started."
    Write-Log "Monitoring processes: $($config.TargetProcesses -join ', ')"

    # Save the original format before applying either profile.
    Save-OriginalFormat

    # Apply the profile matching the current process state.
    Apply-CurrentProfile

    while ($true) {
        $event = Wait-Event -Timeout 5

        if ($null -eq $event) {
            continue
        }

        $source = $event.SourceIdentifier

        try {
            if ($source -like "$sourcePrefix.ProcessStart.*") {
                Start-Sleep -Milliseconds 300

                if (Test-TargetProcessRunning) {
                    Set-MusicProfile
                }
            }
            elseif ($source -like "$sourcePrefix.ProcessStop.*") {
                Start-Sleep -Milliseconds 500

                if (Test-TargetProcessRunning) {
                    Set-MusicProfile
                }
                else {
                    Set-AtmosProfile
                }
            }
            elseif ($source -eq "$sourcePrefix.DefaultDeviceChanged") {
                $deviceEventArgs = $event.SourceEventArgs

                # EDataFlow.Render = 0; ERole.Multimedia = 1.
                if (
                    $deviceEventArgs.Flow -eq 0 -and
                    $deviceEventArgs.Role -eq 1 -and
                    $deviceEventArgs.DeviceId -eq $config.WindowsDeviceId
                ) {
                    Write-Log "Target HDMI endpoint became the default playback device."
                    Apply-CurrentProfile -Force
                }
                else {
                    Write-Log "Default playback device changed to another endpoint. Target profile left unchanged."
                }
            }
        }
        catch {
            Write-Log "Event handling error: $($_.Exception.Message)"
        }
        finally {
            Remove-Event `
                -EventIdentifier $event.EventIdentifier `
                -ErrorAction SilentlyContinue
        }
    }
}
catch {
    Write-Log "Fatal watcher error: $($_.Exception.Message)"
    throw
}
finally {
    Write-Log "AtmosWatcher stopped."

    Get-EventSubscriber |
        Where-Object {
            $_.SourceIdentifier -like "$sourcePrefix.*"
        } |
        Unregister-Event -ErrorAction SilentlyContinue

    Get-Event |
        Where-Object {
            $_.SourceIdentifier -like "$sourcePrefix.*"
        } |
        Remove-Event -ErrorAction SilentlyContinue

    if ($audioWatcher) {
        $audioWatcher.Dispose()
    }
}