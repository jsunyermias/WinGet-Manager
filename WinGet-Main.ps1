<#
WinGet Main Execution Script
Version 0.8
#>

# Requires -RunAsAdministrator
[CmdletBinding()]
param()

# ===============================
# Define constants and paths
# ===============================

# Path to the lock file to prevent parallel executions of this script
$lockFile = Join-Path -Path $env:ProgramData -ChildPath "WinGet-extra\tmp\WinGet-Main.lock"

# Path to the log file, named with current date
$logFile = Join-Path -Path $env:ProgramData -ChildPath "WinGet-extra\logs\WinGet-Main_$(Get-Date -Format 'yyyy-MM-dd').log"

# Directories extracted from above paths, used for folder existence checks
$tmpFolder = Split-Path $lockFile
$logFolder = Split-Path $logFile

# Maximum allowed lock file age in minutes before it is considered stale and removed
$maxLockAgeMinutes = 240

# ===============================
# Create required folders if missing
# ===============================
foreach ($folder in @($tmpFolder, $logFolder)) {
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
}

# ===============================
# Logging function (timestamped)
# ===============================
function Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Write-Output $logMessage
    Add-Content -Path $logFile -Value $logMessage
}

# ===============================
# Lock acquisition to prevent parallel execution
# ===============================
function Acquire-Lock {
    if (Test-Path $lockFile) {
        $lockAge = (Get-Date) - (Get-Item $lockFile).LastWriteTime
        if ($lockAge.TotalMinutes -gt $maxLockAgeMinutes) {
            Log "Lock file is older than $maxLockAgeMinutes minutes. Removing stale lock."
            Remove-Item $lockFile -Force
        } else {
            Log "ERROR: Another instance is already running."
            throw "Lock file exists."
        }
    }
    "$PID - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $lockFile -Encoding ascii -Force
    Log "Lock acquired: $lockFile"
}

# ===============================
# Lock release at the end of execution
# ===============================
function Release-Lock {
    try {
        if (Test-Path $lockFile) {
            Remove-Item $lockFile -Force
            Log "Lock released: $lockFile"
        }
    } catch {
        Log "WARNING: Failed to release lock file: $_"
    }
}

# ===============================
# Check if the script is run as administrator
# ===============================
function Check-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if (-not $isAdmin) {
        Log "WARNING: Script must be run as administrator. Relaunching with elevation..."
        $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"") + $MyInvocation.UnboundArguments
        Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs
        exit
    } else {
        Log "Running with administrative privileges."
    }
}

# ===============================
# Main Execution
# ===============================

try {
    # Verify running with administrator privileges or relaunch elevated
    Check-Admin
    
    # Attempt to acquire lock to prevent parallel execution    
    Acquire-Lock

    Log "===== Starting WinGet Main Script ====="

    # Define the scripts to run
    $scripts = @(
        Join-Path -Path $env:ProgramData -ChildPath "WinGet-extra\WinGet-Maintenance.ps1"
        Join-Path -Path $env:ProgramData -ChildPath "WinGet-extra\WinGet-Upgrade.ps1"
        Join-Path -Path $env:ProgramData -ChildPath "WinGet-extra\WinGet-Clean.ps1"
    )

    # Run scripts one by one
    foreach ($script in $scripts) {
        Log "Running $script..."
        $proc = Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-ExecutionPolicy Bypass -File `"$script`"" `
            -WindowStyle Hidden -Wait -PassThru

        if ($proc.ExitCode -ne 0) {
            Log "ERROR: The script $script failed with code $($proc.ExitCode). Stopping execution."
            break
        } else {
            Log "$script successfully executed."
        }
    }

    Log "===== Script execution completed successfully ====="

} catch {
    Log "ERROR: Script execution failed. $_"
} finally {
    Release-Lock
}
