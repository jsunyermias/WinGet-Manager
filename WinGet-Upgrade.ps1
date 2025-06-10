<#
WinGet Upgrade Script
Version 0.8
#>

# Requires -RunAsAdministrator
[CmdletBinding()]
param()

# ===============================
# Define constants and paths
# ===============================

# Path to the lock file to prevent parallel executions of this script
$lockFile = Join-Path -Path $env:ProgramData -ChildPath "WinGet-extra\tmp\WinGet-Upgrade.lock"

# Path to the log file, named with current date
$logFile = Join-Path -Path $env:ProgramData -ChildPath "WinGet-extra\logs\WinGet-Upgrade_$(Get-Date -Format 'yyyy-MM-dd').log"

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
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    Write-Verbose $logMessage
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
        Log "WARNING: Could not release lock file: $_"
    }
}

# ===============================
# Check if the script is run as administrator
# ===============================
function Check-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if (-not $isAdmin) {
        Log "WARNING: Script must be run as administrator. Restarting with elevation..."
        $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"") + $MyInvocation.UnboundArguments
        Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs
        exit
    } else {
        Log "Running with administrative privileges."
    }
}

# ===============================
# Upgrade a package using its ID
# ===============================
function Upgrade-WinGetPackage {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PackageId
    )

    $pkgFolder = Join-Path $tmpFolder $PackageId
    if (-not (Test-Path $pkgFolder)) {
        New-Item -ItemType Directory -Path $pkgFolder -Force | Out-Null
    }

    Log "Downloading installer for ${PackageId}..."
    $download = Start-Process -FilePath "winget" `
        -ArgumentList "download", "--id", $PackageId, "-d", $pkgFolder, "--accept-source-agreements", "--accept-package-agreements", "--source", "winget" `
        -NoNewWindow -Wait -PassThru

    if ($download.ExitCode -ne 0) {
        Log "ERROR: Failed to download installer for ${PackageId}. Exit code: $($download.ExitCode)"
        return $download.ExitCode
    }

    # Retry logic for specific exit codes
    $retryableExitCodes = @(0x8A150102, 0x8A150103)
    $installTechChangedCode = 0x8A150104
    $maxRetries = 3
    $retryCount = 0

    do {
        Log "Attempting upgrade for ${PackageId} (try $($retryCount + 1)/$maxRetries)..."
        $process = Start-Process -FilePath "winget" `
            -ArgumentList "upgrade", "--id", $PackageId, "-e", "--accept-source-agreements", "--accept-package-agreements", "--source", "winget" `
            -NoNewWindow -Wait -PassThru

        $code = $process.ExitCode

        switch ($code) {
            0x0 {
                Log "${PackageId} upgraded successfully."
                return $code
            }
            0x8A150101 {
                Log "${PackageId} is currently in use — upgrade cannot proceed."
                return $code
            }
            0x8A150111 {
                Log "${PackageId} is currently in use — upgrade cannot proceed."
                return $code
            }
            0x8A15010B {
                Log "${PackageId} requires a reboot to complete the upgrade."
                return $code
            }
            $installTechChangedCode {
                Log "Installation technology changed for ${PackageId}. Proceeding with uninstall and clean install..."
                return Invoke-CleanInstall -PackageId $PackageId
            }
            { $retryableExitCodes -contains $_ } {
                Log "Temporary issue encountered for ${PackageId} (code $code). Retrying in 30 seconds..."
                Start-Sleep -Seconds 30
                $retryCount++
                continue
            }
            default {
                Log "Unknown error (code $code) occurred for ${PackageId}. Attempting uninstall and reinstall."
                return Invoke-CleanInstall -PackageId $PackageId
            }
        }

    } while ($retryCount -lt $maxRetries)

    return $code
}

# ===============================
# Perform uninstall and clean install of a package
# ===============================
function Invoke-CleanInstall {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PackageId
    )

    Log "Starting clean installation process for ${PackageId}..."

    # Step 1: Uninstall the package
    $uninstall = Start-Process -FilePath "winget" `
        -ArgumentList "uninstall", "--id", $PackageId, "-e", "--accept-source-agreements", "--source", "winget" `
        -NoNewWindow -Wait -PassThru

    if ($uninstall.ExitCode -ne 0) {
        Log "WARNING: Failed to uninstall ${PackageId}. Exit code: $($uninstall.ExitCode)"
        # Attempt forced uninstall via downloaded installer
        $installer = Get-ChildItem -Path (Join-Path $tmpFolder $PackageId) -Filter "*.exe" | Select-Object -First 1
        if ($installer) {
            Log "Attempting uninstall using downloaded installer: $($installer.FullName)"
            $uninstallAlt = Start-Process -FilePath $installer.FullName -ArgumentList "/S /uninstall" -Wait -PassThru
            if ($uninstallAlt.ExitCode -eq 0) {
                Log "Successfully uninstalled using downloaded installer."
            } else {
                Log "ERROR: Failed to uninstall using downloaded installer. Exit code: $($uninstallAlt.ExitCode)"
                return $uninstallAlt.ExitCode
            }
        } else {
            return $uninstall.ExitCode
        }
    }

    # Step 2: Perform clean installation
    Log "Performing clean installation of ${PackageId}..."
    $install = Start-Process -FilePath "winget" `
        -ArgumentList "install", "--id", $PackageId, "-e", "--accept-source-agreements", "--accept-package-agreements", "--source", "winget" `
        -NoNewWindow -Wait -PassThru

    if ($install.ExitCode -eq 0) {
        Log "${PackageId} installed successfully."
    } else {
        Log "ERROR: Failed to install ${PackageId}. Exit code: $($install.ExitCode)"
        # Attempt install via downloaded executable
        $installer = Get-ChildItem -Path (Join-Path $tmpFolder $PackageId) -Filter "*.exe" | Select-Object -First 1
        if ($installer) {
            Log "Attempting install using downloaded installer: $($installer.FullName)"
            $installAlt = Start-Process -FilePath $installer.FullName -ArgumentList "/S" -Wait -PassThru
            if ($installAlt.ExitCode -eq 0) {
                Log "Successfully installed using downloaded installer."
            } else {
                Log "ERROR: Failed to install using downloaded installer. Exit code: $($installAlt.ExitCode)"
            }
            return $installAlt.ExitCode
        }
    }

    return $install.ExitCode
}

# ===============================
# Main Execution Block
# ===============================
try {
    # Verify running with administrator privileges or relaunch elevated
    Check-Admin

    # Attempt to acquire lock to prevent parallel execution
    Acquire-Lock
    
    Log "===== Starting WinGet Upgrade Script ====="

    # Import WinGet module if not already loaded
    if (-not (Get-Module -Name Microsoft.WinGet.Client -ErrorAction SilentlyContinue)) {
        Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        Log "Imported Microsoft.WinGet.Client module."
    }

    # Get list of upgradable packages from winget
    $packageList = Get-WinGetPackage | Where-Object { $_.Source -eq 'winget' -and $_.IsUpdateAvailable }

    if ($packageList.Count -eq 0) {
        Log "No updates available."
    } else {
        foreach ($pkg in $packageList) {
            try {
                $pkgId = $pkg.Id
                Log "Upgrading package: ${pkgId}"
                $result = Upgrade-WinGetPackage -PackageId $pkgId
                Log "Result for ${pkgId}: Exit code ${result}"
            } catch {
                Log "ERROR while upgrading package $($pkg.Id): $_"
            }
        }
    }

    Log "===== Script execution completed successfully ====="
} catch {
    Log "UNEXPECTED ERROR: $_"
} finally {
    Release-Lock
}
