function Get-AtmosConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Configuration file not found: $Path"
    }

    $settings = @{}

    foreach ($line in Get-Content -LiteralPath $Path) {
        $line = $line.Trim()

        if (-not $line -or $line.StartsWith("#") -or $line.StartsWith(";")) {
            continue
        }

        $separator = $line.IndexOf("=")

        if ($separator -lt 1) {
            continue
        }

        $key = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim()

        $settings[$key] = $value
    }

    $required = @(
        "TargetProcesses",
        "SoundVolumeViewPath",
        "AudioDevice",
        "WindowsDeviceId",
        "MusicBitDepth",
        "MusicSampleRate",
        "AtmosGuid"
    )

    foreach ($key in $required) {
        if (-not $settings.ContainsKey($key) -or
            [string]::IsNullOrWhiteSpace($settings[$key])) {
            throw "Missing configuration value: $key"
        }
    }

    $processes = @(
        $settings["TargetProcesses"].Split(";") |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
    )

    if ($processes.Count -eq 0) {
        throw "At least one target process must be configured."
    }

    foreach ($process in $processes) {
        if ($process -notmatch '^[a-zA-Z0-9_.-]+\.exe$') {
            throw "Invalid process name: $process"
        }
    }

    if (-not (Test-Path -LiteralPath $settings["SoundVolumeViewPath"])) {
        throw "SoundVolumeView was not found: $($settings['SoundVolumeViewPath'])"
    }

    if ($settings["WindowsDeviceId"] -notmatch '^\{0\.0\.0\.00000000\}\.\{[0-9a-fA-F-]{36}\}$') {
        throw "Invalid Windows audio endpoint ID."
    }

    $bitDepth = 0
    $sampleRate = 0

    if (-not [int]::TryParse($settings["MusicBitDepth"], [ref]$bitDepth)) {
        throw "MusicBitDepth must be a number."
    }

    if (-not [int]::TryParse($settings["MusicSampleRate"], [ref]$sampleRate)) {
        throw "MusicSampleRate must be a number."
    }

    if ($bitDepth -notin @(16, 24, 32)) {
        throw "MusicBitDepth must be 16, 24, or 32."
    }

    if ($sampleRate -lt 8000 -or $sampleRate -gt 384000) {
        throw "MusicSampleRate is outside the supported validation range."
    }

    $atmosGuid = [guid]::Empty

    if (-not [guid]::TryParse($settings["AtmosGuid"], [ref]$atmosGuid)) {
        throw "AtmosGuid is not a valid GUID."
    }

    return [PSCustomObject]@{
        TargetProcesses     = $processes
        SoundVolumeViewPath = $settings["SoundVolumeViewPath"]
        AudioDevice         = $settings["AudioDevice"]
        WindowsDeviceId     = $settings["WindowsDeviceId"]
        MusicBitDepth       = $bitDepth
        MusicSampleRate     = $sampleRate
        AtmosGuid           = "{$($atmosGuid.ToString())}"
    }
}