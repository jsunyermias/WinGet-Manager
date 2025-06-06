# Requires -RunAsAdministrator
[CmdletBinding()]
param()

# Define paths
$lockFile = "C:\ProgramData\WinGet-extra\tmp\WinGet-Upgrade.lock"
$tmpFolder = Split-Path $lockFile
$logFile = "C:\ProgramData\WinGet-extra\logs\WinGet-Upgrade_$(Get-Date -Format 'yyyy-MM-dd').log"
$logFolder = Split-Path $logFile
$maxLockAgeMinutes = 240

# Create necessary folders
if (-not (Test-Path $tmpFolder)) {
    New-Item -ItemType Directory -Path $tmpFolder -Force | Out-Null
}
if (-not (Test-Path $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
}

# Logging function
function Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    Write-Verbose $logMessage
    Add-Content -Path $logFile -Value $logMessage
}

# Acquire lock to prevent concurrent execution
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

# Release lock
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

# Check for admin rights
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

# Upgrade a package using its ID
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
        -ArgumentList "download", "--id", $PackageId, "-d", $pkgFolder, "--accept-source-agreements", "--accept-package-agreements" `
        -NoNewWindow -Wait -PassThru

    if ($download.ExitCode -ne 0) {
        Log "Error downloading installer for ${PackageId}. Exit code: $($download.ExitCode)"
        return $download.ExitCode
    }

    $retryableExitCodes = @(0x8A150102, 0x8A150103)
    $installTechChangedCode = 0x8A150104 # Código específico para tecnología de instalación diferente
    $maxRetries = 3
    $retryCount = 0

    do {
        Log "Attempting upgrade for ${PackageId} (try $($retryCount + 1)/$maxRetries)..."
        $process = Start-Process -FilePath "winget" `
            -ArgumentList "upgrade", "--id", $PackageId, "-e", "--accept-source-agreements", "--accept-package-agreements" `
            -NoNewWindow -Wait -PassThru

        $code = $process.ExitCode

        switch ($code) {
            0x0 {
                Log "${PackageId} upgraded successfully."
                return $code
            }
            0x8A150101 {
                Log "${PackageId} in use — cannot upgrade now."
                return $code
            }
            0x8A150111 {
                Log "${PackageId} in use — cannot upgrade now."
                return $code
            }
            0x8A15010B {
                Log "${PackageId} requires reboot to complete."
                return $code
            }
            $installTechChangedCode {
                Log "Installation technology changed for ${PackageId}. Performing uninstall and fresh install..."
                return Invoke-CleanInstall -PackageId $PackageId
            }
            { $retryableExitCodes -contains $_ } {
                Log "Temporary issue for ${PackageId} (code $code). Retrying in 30 seconds..."
                Start-Sleep -Seconds 30
                $retryCount++
                continue
            }
            default {
                Log "Unknown error (code $code) for ${PackageId}. Attempting uninstall and reinstall."
                return Invoke-CleanInstall -PackageId $PackageId
            }
        }

    } while ($retryCount -lt $maxRetries)

    return $code
}

# Nueva función para manejar desinstalación e instalación limpia
function Invoke-CleanInstall {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PackageId
    )

    Log "Starting clean installation process for ${PackageId}..."
    
    # Paso 1: Desinstalar
    $uninstall = Start-Process -FilePath "winget" `
        -ArgumentList "uninstall", "--id", $PackageId, "-e", "--accept-source-agreements" `
        -NoNewWindow -Wait -PassThru

    if ($uninstall.ExitCode -ne 0) {
        Log "WARNING: Failed to uninstall ${PackageId}. Exit code: $($uninstall.ExitCode)"
        # Intentar forzar la desinstalación con el instalador descargado
        $installer = Get-ChildItem -Path (Join-Path $tmpFolder $PackageId) -Filter "*.exe" | Select-Object -First 1
        if ($installer) {
            Log "Attempting uninstall using downloaded installer: $($installer.FullName)"
            $uninstallAlt = Start-Process -FilePath $installer.FullName -ArgumentList "/S /uninstall" -Wait -PassThru
            if ($uninstallAlt.ExitCode -eq 0) {
                Log "Successfully uninstalled using installer executable"
            } else {
                Log "ERROR: Failed to uninstall using installer. Exit code: $($uninstallAlt.ExitCode)"
                return $uninstallAlt.ExitCode
            }
        } else {
            return $uninstall.ExitCode
        }
    }

    # Paso 2: Instalación limpia
    Log "Performing clean installation of ${PackageId}..."
    $install = Start-Process -FilePath "winget" `
        -ArgumentList "install", "--id", $PackageId, "-e", "--accept-source-agreements", "--accept-package-agreements" `
        -NoNewWindow -Wait -PassThru

    if ($install.ExitCode -eq 0) {
        Log "${PackageId} successfully installed."
    } else {
        Log "ERROR: Failed to install ${PackageId}. Exit code: $($install.ExitCode)"
        # Intentar instalación con el ejecutable descargado
        $installer = Get-ChildItem -Path (Join-Path $tmpFolder $PackageId) -Filter "*.exe" | Select-Object -First 1
        if ($installer) {
            Log "Attempting installation using downloaded installer: $($installer.FullName)"
            $installAlt = Start-Process -FilePath $installer.FullName -ArgumentList "/S" -Wait -PassThru
            if ($installAlt.ExitCode -eq 0) {
                Log "Successfully installed using installer executable"
            } else {
                Log "ERROR: Failed to install using installer. Exit code: $($installAlt.ExitCode)"
            }
            return $installAlt.ExitCode
        }
    }

    return $install.ExitCode
}

# MAIN
try {
    Check-Admin
    Acquire-Lock
    Log "===== Starting WinGet Upgrade Script ====="

    if (-not (Get-Module -Name Microsoft.WinGet.Client -ErrorAction SilentlyContinue)) {
        Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        Log "Imported Microsoft.WinGet.Client module."
    }

    $packageList = Get-WinGetPackage | Where-Object { $_.Source -eq 'winget' -and $_.IsUpdateAvailable }

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
    Log "===== Script execution completed successfully ====="
} catch {
    Log "UNEXPECTED ERROR: $_"
} finally {
    Release-Lock
}
