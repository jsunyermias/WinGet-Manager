
# ===============================
# Define constants and paths
# ===============================
$lockFile = "C:\ProgramData\WinGet-extra\tmp\WinGet-Main.lock"
$logFile = "C:\ProgramData\WinGet-extra\logs\WinGet-Main_$(Get-Date -Format 'yyyy-MM-dd').log"
$logFolder = Split-Path $logFile
$maxLockAgeMinutes = 240

# Crear carpeta de logs si no existe
if (-not (Test-Path $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
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
    Check-Admin
    Acquire-Lock

    $scripts = @(
        "C:\ProgramData\WinGet-extra\WinGet-Maintenance.ps1",
        "C:\ProgramData\WinGet-extra\WinGet-Upgrade.ps1",
        "C:\ProgramData\WinGet-extra\WinGet-Clean.ps1"
    )

    foreach ($script in $scripts) {
        Log "Running $script..."
        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$script`"" -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Log "ERROR: The script $script failed with code $($proc.ExitCode). Stopping execution."
            break
        } else {
            Log "$script successfully executed."
        }
    }

} catch {
    Log "CRITICAL ERROR: $_"
} finally {
    Release-Lock
}
