# Requires -RunAsAdministrator
[CmdletBinding()]
param()

# ===============================
# Define constants and paths
# ===============================

# Path to the lock file to prevent parallel executions of this script
$lockFile = "C:\ProgramData\WinGet-extra\tmp\WinGet-Maintenance.lock"

# Path to the log file, named with current date
$logFile = "C:\ProgramData\WinGet-extra\logs\WinGet-Maintenance_$(Get-Date -Format 'yyyy-MM-dd').log"

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
# Reliable download function with fallback
# ===============================
function Safe-Download {
    param (
        [string[]]$Urls,
        [string]$OutFile
    )
    foreach ($url in $Urls) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $OutFile -ErrorAction Stop
            Log "Successfully downloaded from $url."
            return
        } catch {
            Log "WARNING: Failed to download from $url. Retrying with -UseBasicParsing..."
            try {
                Invoke-WebRequest -Uri $url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
                Log "Downloaded with -UseBasicParsing from $url."
                return
            } catch {
                Log "WARNING: Could not download from $url. $_"
            }
        }
    }
    Log "ERROR: All download attempts failed."
    throw "Download failed for all provided URLs."
}

# ===============================
# Install WinGet if not present
# ===============================
function Install-Winget {
    $output = "$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $urls = @(
        "https://aka.ms/getwinget",
        "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    )
    Safe-Download -Urls $urls -OutFile $output
    Add-AppxPackage -Path $output
    Start-Sleep -Seconds 5
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Log "ERROR: WinGet is still unavailable after installation."
        throw "WinGet installation failed."
    }
}

# ===============================
# Check if WinGet is available
# ===============================
function Check-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Log "WARNING: WinGet not found. Attempting installation..."
        Install-Winget
        Log "WinGet installed successfully."
    } else {
        Log "WinGet is already installed."
    }
}

# ===============================
# Ensure PSGallery is registered and trusted
# ===============================
function Ensure-PSGalleryTrusted {
    try {
        # Disable prompts during provider installation
        $env:NuGet_DisablePromptForProviderInstallation = "true"
        $ProgressPreference = 'SilentlyContinue'

        # Install NuGet provider silently (compatible with PowerShell 5.1)
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue -ListAvailable)) {
            Log "Installing NuGet provider silently..."
            Start-Process -FilePath "powershell.exe" -ArgumentList @(
                "-NoProfile",
                "-ExecutionPolicy Bypass",
                "-Command",
                "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;",
                "Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.208 -Force -ErrorAction Stop | Out-Null"
            ) -Wait -WindowStyle Hidden
        }

        # Register PSGallery if missing
        $psgallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if (-not $psgallery) {
            Log "Registering PSGallery repository."
            Register-PSRepository -Default -ErrorAction Stop | Out-Null
        }

        # Set PSGallery as trusted
        if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne "Trusted") {
            Log "Setting PSGallery as a trusted source."
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop | Out-Null
        }
    } catch {
        Log "ERROR: Failed to configure PSGallery. $_"
        throw $_
    } finally {
        $ProgressPreference = 'Continue'
    }
}

# ===============================
# Ensure WinGet module is installed
# ===============================
function Check-WinGetModule {
    try {
        if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
            Log "Installing Microsoft.WinGet.Client module..."
            Ensure-PSGalleryTrusted
            Start-Process -FilePath "powershell.exe" -ArgumentList @(
                "-NoProfile",
                "-ExecutionPolicy Bypass",
                "-Command",
                "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;",
                "Install-Module -Name Microsoft.WinGet.Client -Force -AllowClobber -Confirm:`$false -SkipPublisherCheck -ErrorAction Stop | Out-Null"
            ) -Wait -WindowStyle Hidden
            Log "Module installed successfully."
        } else {
            Log "Microsoft.WinGet.Client module already installed."
        }
    } catch {
        Log "ERROR: Failed to install Microsoft.WinGet.Client. $_"
        throw $_
    }
}

# ===============================
# Check for and apply WinGet updates
# ===============================
function Check-WinGetUpdates {
    try {
        Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        Log "Microsoft.WinGet.Client module imported."

        $updates = Get-WinGetPackage | Where-Object {
            ($_.Id -in @('Microsoft.AppInstaller', 'Microsoft.DesktopAppInstaller')) -and $_.Source -eq 'winget' -and $_.IsUpdateAvailable
        }

        if ($updates) {
            Log "Found $($updates.Count) update(s)."
            foreach ($pkg in $updates) {
                try {
                    winget upgrade --id $pkg.Id --silent --accept-package-agreements --accept-source-agreements --source winget
                    Log "Upgraded: $($pkg.Id)"
                } catch {
                    Log "WARNING: Failed to upgrade $($pkg.Id). Attempting reinstall..."
                    Install-Winget
                    Log "Reinstalled $($pkg.Id)"
                }
            }
        } else {
            Log "No WinGet-related updates found."
        }
    } catch {
        Log "ERROR: Failed while checking for WinGet updates. $_"
        exit 1
    }
}

# ===============================
# Main Execution Block
# ===============================
try {
    Check-Admin
    Acquire-Lock
    Log "===== Starting WinGet Maintenance Script ====="
    Check-Winget
    Check-WinGetModule
    Check-WinGetUpdates
    Log "===== Script execution completed successfully ====="
} catch {
    Log "ERROR: Script execution failed. $_"
    exit 1
} finally {
    Release-Lock
}
