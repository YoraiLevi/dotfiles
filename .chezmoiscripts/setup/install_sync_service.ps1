# Chezmoi Sync Service Installation Script
# This script creates and starts a Windows Service that runs chezmoi init --apply every 5 minutes
# Requires Administrator privileges

#Requires -RunAsAdministrator

# Configuration
$ServiceName = "ChezmoiSync"
$ServiceDisplayName = "Chezmoi Sync Service"
$ServiceDescription = "Automatically syncs chezmoi dotfiles every 5 minutes by running 'chezmoi init --apply'"
$WrapperScriptSource = Join-Path $PSScriptRoot "chezmoi-sync-service.ps1"
$WrapperScriptDest = "$env:USERPROFILE\.local\bin\chezmoi-sync-service.ps1"
$NssmPath = "$env:USERPROFILE\.local\bin\nssm.exe"
$NssmDownloadUrl = "https://nssm.cc/release/nssm-2.24.zip"
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

# Download and install NSSM if needed
if (-not (Test-Path $NssmPath)) {
    Write-Log "NSSM not found. Downloading..."
    
    try {
        $tempZip = Join-Path $env:TEMP "nssm.zip"
        $tempExtract = Join-Path $env:TEMP "nssm_extract"
        
        # Clean up any existing files
        if (Test-Path $tempZip) { Remove-Item -Path $tempZip -Force }
        if (Test-Path $tempExtract) { Remove-Item -Path $tempExtract -Recurse -Force }
        
        # Download NSSM
        Write-Log "Downloading NSSM from $NssmDownloadUrl..."
        Invoke-WebRequest -Uri $NssmDownloadUrl -OutFile $tempZip -UseBasicParsing
        
        # Extract NSSM using .NET (more compatible)
        Write-Log "Extracting NSSM..."
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $tempExtract)
        
        # Determine architecture and copy appropriate version
        $arch = if ([Environment]::Is64BitOperatingSystem) { "win64" } else { "win32" }
        $nssmExe = Get-ChildItem -Path $tempExtract -Recurse -Filter "nssm.exe" | Where-Object { $_.FullName -like "*$arch*" } | Select-Object -First 1
        
        if (-not $nssmExe) {
            Write-Log "Failed to find NSSM executable in download" "ERROR"
            Write-Log "Available files: $(Get-ChildItem -Path $tempExtract -Recurse -Filter '*.exe' | Select-Object -ExpandProperty FullName)" "ERROR"
            exit 1
        }
        
        # Copy to destination
        $destDir = Split-Path $NssmPath -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item -Path $nssmExe.FullName -Destination $NssmPath -Force
        
        # Cleanup
        Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        
        Write-Log "NSSM installed successfully at $NssmPath" "SUCCESS"
    }
    catch {
        Write-Log "Failed to download/install NSSM: $_" "ERROR"
        Write-Log "Error details: $($_.Exception.Message)" "ERROR"
        exit 1
    }
} else {
    Write-Log "NSSM found at $NssmPath"
}

# Check if service already exists
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Log "Service '$ServiceName' already exists. Stopping and removing..." "WARN"
    
    try {
        # Use NSSM to stop and remove the service
        & $NssmPath stop $ServiceName confirm 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        
        & $NssmPath remove $ServiceName confirm 2>&1 | Out-Null
        
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
$chezmoiPath = "$env:USERPROFILE\.local\bin\chezmoi.exe"
if (-not (Test-Path $chezmoiPath)) {
    Write-Log "WARNING: chezmoi.exe not found at $chezmoiPath - service may fail to run" "WARN"
}

# Get PowerShell path
$pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
Write-Log "PowerShell path: $pwshPath"

# Get current user credentials for the service
Write-Log "Service will run as current user: $env:USERNAME"
Write-Host "`nPlease enter your Windows password to configure the service account:" -ForegroundColor Cyan
$credential = Get-Credential -UserName "$env:USERDOMAIN\$env:USERNAME" -Message "Enter password for service account"

if (-not $credential) {
    Write-Log "Credential input cancelled" "ERROR"
    exit 1
}

# Create the service using NSSM
try {
    Write-Log "Creating service using NSSM..."
    
    # Install the service
    $result = & $NssmPath install $ServiceName $pwshPath "-NoProfile" "-ExecutionPolicy" "Bypass" "-File" "`"$WrapperScriptDest`"" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "NSSM install failed: $result" "ERROR"
        exit 1
    }
    
    # Set display name
    & $NssmPath set $ServiceName DisplayName $ServiceDisplayName | Out-Null
    
    # Set description
    & $NssmPath set $ServiceName Description $ServiceDescription | Out-Null
    
    # Set startup type to automatic
    & $NssmPath set $ServiceName Start SERVICE_AUTO_START | Out-Null
    
    # Set user account
    $username = $credential.UserName
    $password = $credential.GetNetworkCredential().Password
    & $NssmPath set $ServiceName ObjectName $username $password | Out-Null
    
    # Set working directory to user profile
    & $NssmPath set $ServiceName AppDirectory $env:USERPROFILE | Out-Null
    
    # Configure stdout/stderr logging
    $serviceLogDir = "$env:USERPROFILE\.local\share\chezmoi-sync\logs"
    & $NssmPath set $ServiceName AppStdout "$serviceLogDir\nssm-stdout.log" | Out-Null
    & $NssmPath set $ServiceName AppStderr "$serviceLogDir\nssm-stderr.log" | Out-Null
    
    Write-Log "Service created successfully using NSSM" "SUCCESS"
}
catch {
    Write-Log "Failed to create service: $_" "ERROR"
    Write-Log "Error details: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Start the service
try {
    Write-Log "Starting service..."
    
    & $NssmPath start $ServiceName 2>&1 | Out-Null
    
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
