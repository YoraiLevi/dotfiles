# Chezmoi Sync Service Uninstallation Script
# This script stops and removes the Chezmoi Sync Windows Service
# Requires Administrator privileges

#Requires -RunAsAdministrator

# Configuration
$ServiceName = "ChezmoiSync"
$WrapperScriptPath = "$env:USERPROFILE\.local\bin\chezmoi-sync-service.ps1"
$NssmPath = "$env:USERPROFILE\.local\bin\nssm.exe"
$LogFile = "$env:USERPROFILE\.local\share\chezmoi-sync\logs\uninstall.log"

# Function to write log entries
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Ensure log directory exists
    $logDir = Split-Path $LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    Add-Content -Path $LogFile -Value $logMessage
    
    # Color output based on level
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARN"  { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage }
    }
}

# Check if running as Administrator
try {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Log "This script requires Administrator privileges. Please run as Administrator." "ERROR"
        exit 1
    }
} catch {
    Write-Log "Failed to check Administrator privileges: $_" "ERROR"
    exit 1
}

Write-Log "Starting Chezmoi Sync Service uninstallation..."

# Check if service exists
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if (-not $service) {
    Write-Log "Service '$ServiceName' not found - nothing to uninstall" "WARN"
} else {
    Write-Log "Found service: $($service.DisplayName)"
    
    # Check if NSSM is available
    if (Test-Path $NssmPath) {
        Write-Log "Using NSSM to remove service..."
        
        try {
            # Stop the service
            & $NssmPath stop $ServiceName confirm 2>&1 | Out-Null
            Write-Log "Service stopped"
            Start-Sleep -Seconds 2
            
            # Remove the service
            & $NssmPath remove $ServiceName confirm 2>&1 | Out-Null
            Write-Log "Service removed successfully using NSSM" "SUCCESS"
            Start-Sleep -Seconds 2
        }
        catch {
            Write-Log "Error removing service with NSSM: $_" "ERROR"
            exit 1
        }
    } else {
        # Fallback to standard service removal
        Write-Log "NSSM not found, using standard service removal..."
        
        # Stop the service if running
        try {
            if ($service.Status -eq 'Running') {
                Write-Log "Stopping service..."
                Stop-Service -Name $ServiceName -Force -ErrorAction Stop
                Write-Log "Service stopped successfully" "SUCCESS"
                
                # Wait for service to fully stop
                Start-Sleep -Seconds 2
            } else {
                Write-Log "Service is already stopped (Status: $($service.Status))"
            }
        }
        catch {
            Write-Log "Error stopping service: $_" "ERROR"
            Write-Log "Attempting to continue with removal..." "WARN"
        }
        
        # Remove the service
        try {
            Write-Log "Removing service..."
            
            # Use sc.exe for reliable service deletion
            $result = sc.exe delete $ServiceName 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Service removed successfully" "SUCCESS"
            } else {
                Write-Log "Failed to remove service: $result" "ERROR"
                exit 1
            }
            
            # Wait for service to be fully removed
            Start-Sleep -Seconds 2
        }
        catch {
            Write-Log "Error removing service: $_" "ERROR"
            exit 1
        }
    }
}

# Clean up wrapper script
if (Test-Path $WrapperScriptPath) {
    try {
        Write-Log "Removing wrapper script: $WrapperScriptPath"
        Remove-Item -Path $WrapperScriptPath -Force -ErrorAction Stop
        Write-Log "Wrapper script removed successfully" "SUCCESS"
    }
    catch {
        Write-Log "Failed to remove wrapper script: $_" "ERROR"
        Write-Log "You may need to manually delete: $WrapperScriptPath" "WARN"
    }
} else {
    Write-Log "Wrapper script not found at: $WrapperScriptPath"
}

# Summary
Write-Log "`nUninstallation completed!" "SUCCESS"
Write-Log "Service '$ServiceName' has been removed from the system"
Write-Log "`nNote: Log files have been preserved in: $env:USERPROFILE\.local\share\chezmoi-sync\logs\"
Write-Log "You can manually delete these if no longer needed"
