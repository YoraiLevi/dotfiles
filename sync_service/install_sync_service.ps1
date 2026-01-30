# Chezmoi Sync Service Installation Script
# This script creates and starts a Windows Service that runs chezmoi init --apply every 5 minutes
# Requires Administrator privileges and Servy to be installed

#Requires -RunAsAdministrator

# Configuration
$ServiceName = "ChezmoiSync"
$ServiceDisplayName = "Chezmoi Sync Service"
$ServiceDescription = "Automatically syncs chezmoi dotfiles every 5 minutes by running 'chezmoi init --apply'"
$WrapperScriptSource = Join-Path $PSScriptRoot "chezmoi-sync-service.ps1"
$WrapperScriptDest = "$env:USERPROFILE\.local\bin\chezmoi-sync-service.ps1"
$ServyModulePath = "C:\Program Files\Servy\Servy.psm1"
$LogFile = "$env:USERPROFILE\.local\share\chezmoi-sync\logs\install.log"

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

Write-Log "Starting Chezmoi Sync Service installation..."

# Import Servy PowerShell Module
try {
    if (-not (Test-Path $ServyModulePath)) {
        Write-Log "Servy module not found at $ServyModulePath" "ERROR"
        Write-Log "Please ensure Servy is installed: https://github.com/aelassas/servy" "ERROR"
        exit 1
    }
    
    Import-Module $ServyModulePath -Force
    Write-Log "Servy PowerShell module loaded successfully"
}
catch {
    Write-Log "Failed to load Servy module: $_" "ERROR"
    exit 1
}

# Check if service already exists
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Log "Service '$ServiceName' already exists. Stopping and removing..." "WARN"
    
    try {
        # Use Servy to stop and remove the service
        Stop-ServyService -Quiet -Name $ServiceName
        Start-Sleep -Seconds 2
        
        Uninstall-ServyService -Quiet -Name $ServiceName
        
        Write-Log "Existing service removed"
        Start-Sleep -Seconds 2
    }
    catch {
        Write-Log "Error removing existing service: $_" "ERROR"
        exit 1
    }
}

# Check if wrapper script exists
if (-not (Test-Path $WrapperScriptSource)) {
    Write-Log "Wrapper script not found at $WrapperScriptSource" "ERROR"
    exit 1
}

# Copy wrapper script to permanent location
try {
    $destDir = Split-Path $WrapperScriptDest -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        Write-Log "Created directory: $destDir"
    }
    
    Copy-Item -Path $WrapperScriptSource -Destination $WrapperScriptDest -Force
    Write-Log "Wrapper script copied to: $WrapperScriptDest" "SUCCESS"
}
catch {
    Write-Log "Failed to copy wrapper script: $_" "ERROR"
    exit 1
}

# Check if chezmoi.exe exists
$chezmoiPath = (get-command chezmoi).Source
if (-not (Test-Path $chezmoiPath)) {
    Write-Log "WARNING: chezmoi.exe not found at $chezmoiPath - service may fail to run" "WARN"
}

# Get PowerShell path (prefer pwsh.exe, fallback to powershell.exe)
$pwshPath = $null
try {
    $pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
    Write-Log "Using PowerShell Core: $pwshPath"
}
catch {
    try {
        $pwshPath = (Get-Command powershell.exe -ErrorAction Stop).Source
        Write-Log "Using Windows PowerShell: $pwshPath"
    }
    catch {
        Write-Log "Neither pwsh.exe nor powershell.exe found in PATH" "ERROR"
        exit 1
    }
}

# Get current user credentials for the service
Write-Log "Service will run as current user: $env:USERNAME"
Write-Host "`nPlease enter your Windows password to configure the service account:" -ForegroundColor Cyan
$credential = Get-Credential -UserName "$env:USERDOMAIN\$env:USERNAME" -Message "Enter password for service account"

if (-not $credential) {
    Write-Log "Credential input cancelled" "ERROR"
    exit 1
}

# Create the service using Servy
try {
    Write-Log "Creating service using Servy..."
    
    $username = $credential.UserName
    $password = $credential.GetNetworkCredential().Password
    $serviceLogDir = "$env:USERPROFILE\.local\share\chezmoi-sync\logs"
    
    # Ensure log directory exists
    if (-not (Test-Path $serviceLogDir)) {
        New-Item -ItemType Directory -Path $serviceLogDir -Force | Out-Null
    }
    
    # Install the service using Servy PowerShell Module
    Install-ServyService `
        -Quiet `
        -Name $ServiceName `
        -DisplayName $ServiceDisplayName `
        -Description $ServiceDescription `
        -Path $pwshPath `
        -StartupDir $env:USERPROFILE `
        -Params "-NoProfile -ExecutionPolicy Bypass -File `"$WrapperScriptDest`"" `
        -StartupType "Automatic" `
        -Priority "Normal" `
        -Stdout "$serviceLogDir\service-stdout.log" `
        -Stderr "$serviceLogDir\service-stderr.log" `
        -EnableSizeRotation `
        -RotationSize "10" `
        -MaxRotations "5" `
        -User $username `
        -Password $password
    
    Write-Log "Service created successfully using Servy" "SUCCESS"
}
catch {
    Write-Log "Failed to create service: $_" "ERROR"
    Write-Log "Error details: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Start the service
try {
    Write-Log "Starting service..."
    
    Start-ServyService -Quiet -Name $ServiceName
    
    # Wait a moment and check status
    Start-Sleep -Seconds 3
    
    $service = Get-Service -Name $ServiceName
    
    if ($service.Status -eq 'Running') {
        Write-Log "Service started successfully and is running" "SUCCESS"
    } else {
        Write-Log "Service status: $($service.Status)" "WARN"
    }
}
catch {
    Write-Log "Failed to start service: $_" "ERROR"
    Write-Log "You can try starting it manually with: Start-Service -Name $ServiceName" "WARN"
}

# Display service information
Write-Log "`nService installation completed!" "SUCCESS"
Write-Log "Service Name: $ServiceName"
Write-Log "Display Name: $ServiceDisplayName"
Write-Log "Wrapper Script: $WrapperScriptDest"
Write-Log "Log File: $env:USERPROFILE\.local\share\chezmoi-sync\logs\sync-service.log"
Write-Log "`nTo check service status: Get-Service -Name $ServiceName"
Write-Log "To view logs: Get-Content '$env:USERPROFILE\.local\share\chezmoi-sync\logs\sync-service.log' -Tail 20"
