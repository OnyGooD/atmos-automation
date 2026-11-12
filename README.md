# Atmos Automation

Event-driven audio profile automation for Windows 11.

Atmos Automation automatically switches a configured audio endpoint between a music profile and Dolby Atmos for Home Theater.

## Features

- Monitors configured Windows processes.
- Activates the music profile when any monitored process starts.
- Restores the original audio format when all monitored processes exit.
- Disables Spatial Sound while the music profile is active.
- Enables Dolby Atmos for Home Theater when no monitored process is running.
- Monitors Windows default playback device changes.
- Reapplies the appropriate profile when the configured endpoint becomes the default playback device.
- Leaves the target endpoint unchanged when another playback device becomes the Windows default.
- Uses event-driven process and audio-device notifications instead of continuous polling.
- Avoids unnecessary SoundVolumeView calls when the active profile does not need to change.

## Requirements

- Windows 11
- Windows PowerShell 5.1
- SoundVolumeView
- A compatible audio endpoint
- Dolby Atmos for Home Theater support

## Project Structure

- `AtmosWatcher.ps1` - Main event-driven watcher.
- `Config.ps1` - Configuration parser and validation.
- `config.txt` - Your own configuration.
- `Install.ps1` - Installer.
- `Uninstall.ps1` - Uninstaller.
- `LaunchWatcher.vbs` - Hidden PowerShell launcher.
- `LICENSE` - MIT License.

## Configuration

1. Open `config.txt`.
2. Set the process names you want to monitor.
3. Set the path to SoundVolumeView.
4. Set the SoundVolumeView device identifier.
5. Set the Windows Core Audio endpoint ID.
6. Configure the desired music bit depth and sample rate.
7. Set the Dolby Atmos spatial audio GUID.

Multiple processes can be separated with semicolons.

Example:

    TargetProcesses=PlayerA.exe;PlayerB.exe

The music profile remains active while at least one configured process is running.

## Installation

1. Configure `config.txt`.
2. Open PowerShell as Administrator.
3. Navigate to the project directory.
4. Run:

    .\Install.ps1

The installer copies the required files to:

    C:\Programs\AtmosAutomation

It also creates a Windows Task Scheduler task named:

    Atmos Automation

The watcher starts automatically when the user logs in.

## Manual Launch

Run:

    .\LaunchWatcher.vbs

## Uninstallation

Open PowerShell as Administrator and run:

    .\Uninstall.ps1

The saved original audio format and log files are kept in:

    %LOCALAPPDATA%\AtmosAutomation

## Logging

The watcher writes its log to:

    %LOCALAPPDATA%\AtmosAutomation\automation.log

## License

This project is licensed under the MIT License.