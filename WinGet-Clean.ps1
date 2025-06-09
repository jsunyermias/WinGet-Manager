# Requires -RunAsAdministrator
[CmdletBinding()]
param()

# ===============================
# Define constants and paths
# ===============================

# Path to the lock file to prevent parallel executions of this script
$lockFile = Join-Path -Path $env:ProgramData -ChildPath  "WinGet-extra\tmp\WinGet-Clean.lock"

# Path to the log file, named with current date
$logFile = Join-Path -Path $env:ProgramData -ChildPath  "WinGet-extra\logs\WinGet-Clean_$(Get-Date -Format 'yyyy-MM-dd').log"

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
# Define versions to keep for logs and tmp separately
# ===============================
$VersionsToKeepForLogs = 30
$VersionsToKeepForTmp = 10

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
# Cleaning function, main purpose of this script
# ===============================
function Remove-OldFilesByType {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Folder,

        [Parameter(Mandatory = $true)]
        [int]$VersionsToKeep
    )
    
    Write-Verbose "DEBUG: Processing folder $Folder, keeping $VersionsToKeep versions."
    
    # Verify the target folder exists before proceeding
    if (-Not (Test-Path $Folder)) {
        Log "ERROR: The directory '$Folder' does not exist."
        throw "The directory does not exist."
    }

    # Get all files in the target folder (no recursion)
    $files = Get-ChildItem -Path $Folder -File

    # If no files found, log info and exit function
    if ($files.Count -eq 0) {
        Log "INFO: No files found in the specified directory: $Folder"
        return
    }

    Write-Verbose "DEBUG: Found $($files.Count) files in $Folder"
    Write-Verbose "DEBUG: Found $($groupedFiles.Count) file extension groups"

    # Group files by their extension (file type)
    $groupedFiles = $files | Group-Object Extension

    # Iterate through each file type group
    foreach ($fileGroup in $groupedFiles) {
        Log "INFO: Processing file extension group: $($fileGroup.Name)"

        # Sort files by LastWriteTime descending (newest first)
        $sortedFiles = $fileGroup.Group | Sort-Object LastWriteTime -Descending

        # Select the newest files to keep
        $filesToKeep = $sortedFiles | Select-Object -First $VersionsToKeep
        # Files to remove are those beyond the VersionsToKeep threshold
        $filesToRemove = $sortedFiles | Select-Object -Skip $VersionsToKeep

        # Remove the older files
        foreach ($file in $filesToRemove) {
            Write-Host "DEBUG: Deleting file $($file.FullName)"
            try {
                Remove-Item -Path $file.FullName -Force
                Log "INFO: Deleted file: $($file.FullName)"
            }
            catch {
                Log "WARNING: Failed to delete file: $($file.FullName) - $_"
            }
        }
    }
}

# ===============================
# Main Execution Block
# ===============================

try {
    # Verify running with administrator privileges or relaunch elevated
    Check-Admin

    # Attempt to acquire lock to prevent parallel execution
    Acquire-Lock

    # Clean the logs older than 30 versions (files)
    Remove-OldFilesByType -Folder $logFolder -VersionsToKeep $VersionsToKeepForLogs

    # Clean all subdirectories inside $tmpFolder
    $subDirs = Get-ChildItem -Path $tmpFolder -Directory

    foreach ($dir in $subDirs) {
        Log "INFO: Cleaning folder: $($dir.FullName)"
        try {
            Remove-OldFilesByType -Folder $dir.FullName -VersionsToKeep $VersionsToKeepForTmp
        }
        catch {
            Log "WARNING: Failed to clean folder $($dir.FullName) - $_"
        }
    }

} catch {
    # Log any unexpected errors
    Log "ERROR: Unexpected error occurred: $_"
} finally {
    # Always release the lock file even if errors occurred
    Release-Lock
}
