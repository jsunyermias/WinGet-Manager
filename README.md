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