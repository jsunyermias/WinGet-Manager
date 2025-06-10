# WinGet-Manager
PowerShell scripts to get WinGet automatically managed


## 📄 WinGet-Main.vbs

This VBS script is designed to automatically run a PowerShell script with administrator privileges, silently and in the background. It’s useful for tasks that require elevation without manual user intervention (beyond the UAC prompt).

### 🔧 What does it do?

Checks that the WinGet-Main.ps1 script exists in %ProgramData%\WinGet-extra\.

Verifies if it is running with administrator privileges.

If not elevated, relaunches the PowerShell script with elevated privileges (runas).

If already elevated, runs the PowerShell script silently in the background.


### 📁 Requirements

Place WinGet-Main.ps1 at:
%ProgramData%\WinGet-extra\WinGet-Main.ps1

Run WinGet-Main.vbs by double-click or from the command line.


### 📌 Notes

Uses ShellExecute to elevate permissions via UAC.

Creates a temporary file admin-test.tmp to check write permissions in %ProgramData%.


---


## 📄 WinGet-Main.ps1

This PowerShell script runs a sequence of WinGet-related maintenance, upgrade, and cleanup scripts, ensuring that only one instance runs at a time by using a lock file. It requires administrator privileges and logs its activity with timestamps.

### 🔧 What does it do?

Checks if the script is running with administrator rights, and relaunches itself with elevation if needed.

Prevents multiple simultaneous executions by creating and managing a lock file with an automatic stale-lock cleanup after 240 minutes.

Executes three scripts sequentially from %ProgramData%\WinGet-extra\:

WinGet-Maintenance.ps1

WinGet-Upgrade.ps1

WinGet-Clean.ps1

Logs all operations, errors, and script statuses to daily log files in %ProgramData%\WinGet-extra\logs\.


### 📁 Requirements

PowerShell with administrative privileges (the script self-elevates if run without them).

Secondary scripts located at:

%ProgramData%\WinGet-extra\WinGet-Maintenance.ps1
%ProgramData%\WinGet-extra\WinGet-Upgrade.ps1
%ProgramData%\WinGet-extra\WinGet-Clean.ps1

Permissions to create and write files in:

%ProgramData%\WinGet-extra\tmp\
%ProgramData%\WinGet-extra\logs\


### 📌 Notes

The lock file located at %ProgramData%\WinGet-extra\tmp\WinGet-Main.lock prevents parallel runs and is removed automatically if older than 240 minutes.

Logs are saved daily with timestamps in %ProgramData%\WinGet-extra\logs\WinGet-Main_YYYY-MM-DD.log.

If any secondary script fails (non-zero exit code), the main script stops execution and logs the failure.

The script creates required folders if they do not exist.


---


## 📄 WinGet-Maintenance.ps1

This PowerShell script is designed to manage the maintenance of WinGet on Windows systems, ensuring it is installed, updated, and functioning properly, with controls to prevent parallel executions and manage administrator permissions.

### 🔧 What does it do?

Checks if WinGet is installed, and if not, installs it automatically from official sources.

Installs and imports the Microsoft.WinGet.Client module needed for package management.

Checks for updates to key WinGet packages (such as Microsoft.DesktopAppInstaller) and applies them automatically.

Prevents parallel executions using a lock file with configurable expiration.

Logs events and errors in daily log files for tracking.

Verifies and ensures the script always runs with administrator privileges, relaunching with elevation if necessary.

Ensures the PSGallery repository is registered and trusted for module installation.


### 📁 Requirements

Run the script with administrator permissions, or let it auto-elevate itself.

Recommended location for logs and temporary files: %ProgramData%\WinGet-extra\ (the script creates folders if missing).

PowerShell 5.1 or higher.


### 📌 Notes

Uses a lock file (WinGet-Maintenance.lock) to avoid simultaneous multiple instances running.

Supports secure downloading with retries from multiple URLs to install WinGet if missing.

Logs are stored with date stamps in %ProgramData%\WinGet-extra\logs\ for easy auditing.

Silently manages NuGet provider installation and PSGallery repository configuration to avoid interruptions.

On critical errors, logs the issue and stops execution, releasing the lock.

Requires internet connection to download installers and updates.