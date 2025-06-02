# Requires -RunAsAdministrator
[CmdletBinding()]
param()

# Define paths
$lockFile = "C:\ProgramData\WinGet-extra\tmp\WinGet-Maintenance.lock"
$tmpFolder = Split-Path $lockFile
$logFile = "C:\ProgramData\WinGet-extra\logs\WinGet-Maintenance_$(Get-Date -Format 'yyyy-MM-dd').log"
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
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
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

# Safe download function with fallback
function Safe-InvokeWebRequest {
    param (
        [string]$Uri,
        [string]$OutFile
    )
    try {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -ErrorAction Stop
        Log "Downloaded successfully without -UseBasicParsing."
    } catch {
        Log "WARNING: Failed without -UseBasicParsing. Retrying with it..."
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
            Log "Downloaded successfully using -UseBasicParsing."
        } catch {
            Log "ERROR: Failed to download file. $_"
            throw $_
        }
    }
}

# Check if winget is installed
function Check-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Log "WARNING: winget not found. Attempting to install..."

        $output = "$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"

        try {
            $url = "https://aka.ms/getwinget"
            Safe-InvokeWebRequest -Uri $url -OutFile $output
            Add-AppxPackage -Path $output
            Log "Installed WinGet from aka.ms/getwinget."
        } catch {
            Log "WARNING: Failed to install from aka.ms/getwinget. Trying fallback URL (WinGet GitHub Repository)..."
            try {
                $fallbackUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
                Safe-InvokeWebRequest -Uri $fallbackUrl -OutFile $output
                Add-AppxPackage -Path $output
                Log "Installed WinGet from fallback URL (WinGet GitHub Repository)."
            } catch {
                Log "ERROR: Failed to install WinGet from all sources. $_"
                throw $_
            }
        }

        Start-Sleep -Seconds 5
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Log "ERROR: WinGet command still unavailable after installation."
            throw "WinGet not found after install."
        }
    } else {
        Log "WinGet is already installed."
    }
}

# Ensure PSGallery is available and trusted
function Ensure-PSGalleryTrusted {
    try {
        $psgallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if (-not $psgallery) {
            Log "Registering PSGallery repository."
            Register-PSRepository -Default -ErrorAction Stop
        } elseif ($psgallery.InstallationPolicy -ne "Trusted") {
            Log "Setting PSGallery repository as Trusted."
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
        }
    } catch {
        Log "ERROR: Failed to configure PSGallery. $_"
        throw $_
    }
}

# Check or install Microsoft.WinGet.Client module
function Check-WinGetModule {
    try {
        if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
            Log "Installing Microsoft.WinGet.Client module..."
            Ensure-PSGalleryTrusted
            Install-Module -Name Microsoft.WinGet.Client -Force -Confirm:$false -AllowClobber -ErrorAction Stop
            Log "Module installed successfully."
        } else {
            Log "Microsoft.WinGet.Client module already present."
        }
    } catch {
        Log "ERROR: Failed to install Microsoft.WinGet.Client. $_"
        throw $_
    }
}

# Check and apply WinGet updates
function Check-WingetUpdates {
    try {
        if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop
            Log "Imported Microsoft.WinGet.Client module."
        }

        $updates = Get-WinGetPackage | Where-Object {
            ($_.Id -eq 'Microsoft.AppInstaller' -or $_.Id -eq 'Microsoft.DesktopAppInstaller') -and $_.Source -eq 'winget' -and $_.IsUpdateAvailable
        }

        if ($updates) {
            Log "Found $($updates.Count) update(s) for WinGet-related packages."
            foreach ($pkg in $updates) {
                try {
                    winget upgrade --id $pkg.Id --silent --accept-package-agreements --accept-source-agreements
                    Log "Upgraded: $($pkg.Id)"
                } catch {
                    Log "WARNING: Failed to upgrade $($pkg.Id). Trying manual reinstall..."
                    $output = "$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
                    try {
                        $url = "https://aka.ms/getwinget"
                        Safe-InvokeWebRequest -Uri $url -OutFile $output
                        Add-AppxPackage -Path $output
                        Log "Reinstalled $($pkg.Id) from aka.ms/getwinget."
                    } catch {
                        try {
                            $fallbackUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
                            Safe-InvokeWebRequest -Uri $fallbackUrl -OutFile $output
                            Add-AppxPackage -Path $output
                            Log "Reinstalled $($pkg.Id) from fallback URL."
                        } catch {
                            Log "ERROR: Could not reinstall $($pkg.Id). $_"
                            throw $_
                        }
                    }
                }
            }
        } else {
            Log "No updates available for WinGet-related packages."
        }
    } catch {
        Log "ERROR: Failed during WinGet update check. $_"
        exit 1
    }
}

# Main execution block
try {
    Acquire-Lock
    Log "===== Starting WinGet Maintenance Script ====="
    Check-Admin
    Check-Winget
    Check-WinGetModule
    Check-WingetUpdates
    Log "===== Script Execution Completed Successfully ====="
} catch {
    Log "ERROR: Script failed. $_"
    exit 1
} finally {
    Release-Lock
}
