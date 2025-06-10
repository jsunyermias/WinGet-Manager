# WinGet-Manager

This project automates system maintenance using **WinGet** and **PowerShell**, centralizing all scripts, logs, and temporary files under `%ProgramData%\WinGet-extra`.

## Script Structure

### `Winget-Main.ps1`
The main script that runs the following scripts sequentially:
1. [`WinGet-Maintenance.ps1`](#winget-maintenanceps1)
2. [`WinGet-Upgrade.ps1`](#winget-upgradeps1)
3. [`WinGet-Clean.ps1`](#winget-cleanps1)

### `WinGet-Maintenance.ps1`
Checks for and installs if necessary:
- `WinGet`
- The PowerShell module `Microsoft.WinGet.Client`

This ensures the system is ready to use advanced WinGet commands from PowerShell.

### `WinGet-Upgrade.ps1`
- Checks for available updates for WinGet-managed packages.
- Updates packages one by one if updates are found.
- Saves a local copy of downloaded installers/updaters.

### `WinGet-Clean.ps1`
- Cleans up old temporary files and logs.
- Keeps a configurable minimum number of:
  - Execution logs
  - Installation or update files

## File Location

All scripts and related files are located at:

%ProgramData%\WinGet-extra\

This includes:
- Scripts (`*.ps1`,`*.vbs`)
- Logs (`logs`)
- Downloaded installers (`tmp\$PackageId`)
- Temporary files (`tmp`)

## Usage

1. **Run as Administrator:**  
   Elevated permissions are required to install, update, and clean system packages.

2. **Manual Execution:**  
   Run the main script manually with the following command:
   ```powershell
   powershell -ExecutionPolicy Bypass -File "%ProgramData%\WinGet-extra\Winget-Main.ps1"

3. Scheduled Task:
It is recommended to create a scheduled task to run Winget-Main.ps1 periodically (e.g., weekly).


## Requirements

Windows 10/11 with WinGet support

PowerShell 5.1 or newer

Internet connection

Administrator privileges


Notes

The system runs non-interactively, making it ideal for automated environments.

Cleanup routines retain a configurable minimum history.

The system can be extended to include other package managers or maintenance tools.
