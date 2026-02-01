# Requires Administrator privileges
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Chezmoi Sync Service Installer and Uninstaller

.DESCRIPTION
    Installs, reinstalls, or uninstalls a Windows Service that periodically runs chezmoi to apply dotfiles (every 5 minutes).
    - Requires Administrator privileges.
    - Depends on the Servy PowerShell module.

.PARAMETER Uninstall
    Switch to uninstall the service instead of installing it.

.PARAMETER ServiceName
    The internal Windows service name (letters, numbers, underscore allowed).

.PARAMETER ServiceDisplayName
    The display name shown in Windows Services.

.PARAMETER ServiceDescription
    The Windows service description.

.PARAMETER WrapperScriptSource
    Source path of the chezmoi sync PowerShell script (should be an existing .ps1 file).

.PARAMETER WrapperScriptDest
    Directory to copy/store the chezmoi sync wrapper script for the service.

.PARAMETER ServyModulePath
    Path to the Servy PowerShell module (.psm1 file).

.PARAMETER ServiceDir
    The root directory under which sync state (logs etc.) will be maintained.

.PARAMETER InstallLogDir
    Directory for setup/install log output.

.PARAMETER Credentials
    Windows credential to run the service under. If not provided, will be prompted.

.PARAMETER pwshPath
    Path to pwsh.exe or powershell.exe.

.PARAMETER LogFileName
    File name for the per-service log file (created under ServiceDir\logs).

.EXAMPLE
    # Install mode
    .\install_sync_service.ps1 `
        -ServiceName "Chezmoi_Sync_1" `
        -ServiceDisplayName "Chezmoi Sync Service" `
        -ServiceDescription "Automatically syncs chezmoi dotfiles." `
        -WrapperScriptSource "C:\Path\to\chezmoi-sync-service.ps1" `
        -WrapperScriptDest "$env:USERPROFILE\.local\bin" `
        -ServyModulePath "C:\Program Files\Servy\Servy.psm1" `
        -ServiceDir "$env:USERPROFILE\.local\share\chezmoi-sync\" `
        -InstallLogDir "$env:USERPROFILE\.local\share\chezmoi-sync\logs" `
        -Credentials (Get-Credential) `
        -pwshPath "C:\Program Files\PowerShell\7\pwsh.exe"

.EXAMPLE
    # Uninstall mode
    .\install_sync_service.ps1 -Uninstall -ServiceName "ChezmoiSync"
#>

[CmdletBinding(DefaultParameterSetName = "Install")]
param(
    # Uninstall switch - only for Uninstall parameter set
    [Parameter(ParameterSetName = "Uninstall", Mandatory = $true)]
    [switch]$Uninstall,

    # Shared parameters (both Install and Uninstall)
    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Uninstall")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern("^[a-zA-Z0-9_]+$")] # Allow only alphanumerics + underscore for service name
    [string]$ServiceName = "ChezmoiSync",

    # Install-only parameters
    [Parameter(ParameterSetName = "Install")]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceDisplayName = "Chezmoi Sync Service",

    [Parameter(ParameterSetName = "Install")]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceDescription = "Automatically syncs chezmoi dotfiles every 5 minutes by running 'chezmoi init --apply'",

    [Parameter(ParameterSetName = "Install")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
            if (-not (Test-Path $_)) {
                throw "WrapperScriptSource file '$_' does not exist."
            }
            if (-not (Test-Path $_ -PathType Leaf)) {
                throw "WrapperScriptSource '$_' is not a file."
            }
            $true
        })]
    [string]$WrapperScriptSource = $(Join-Path $PSScriptRoot "chezmoi-sync-service.ps1"),

    # Shared parameter (needed for both install and uninstall)
    # Note: Validation is relaxed for uninstall mode - handled in script body
    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Uninstall")]
    [ValidateNotNullOrEmpty()]
    [string]$WrapperScriptDest = "$env:USERPROFILE\.local\bin",

    # Shared parameter (needed for both install and uninstall)
    # Note: Validation is relaxed for uninstall mode - handled in script body
    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Uninstall")]
    [ValidateNotNullOrEmpty()]
    [string]$ServyModulePath = $(
        try {
            $servyExe = Get-Command servy.exe -ErrorAction Stop
            $servyDir = Split-Path $servyExe.Source -Parent
            Join-Path $servyDir "servy.psm1"
        }
        catch {
            "C:\Program Files\Servy\Servy.psm1"
        }
    ),

    # Install-only parameter
    [Parameter(ParameterSetName = "Install")]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceDir = "$env:USERPROFILE\.local\share\chezmoi-sync\",

    # Shared parameter (needed for both install and uninstall logs)
    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Uninstall")]
    [ValidateNotNullOrEmpty()]
    [string]$InstallLogDir = "$env:USERPROFILE\.local\share\chezmoi-sync\logs",

    # Install-only parameter
    [Parameter(ParameterSetName = "Install", Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credentials,

    # Install-only parameter
    [Parameter(ParameterSetName = "Install")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
            if (-not (Test-Path $_)) {
                throw "pwshPath '$_' does not exist."
            }
            if (-not (Test-Path $_ -PathType Leaf)) {
                throw "pwshPath '$_' is not a file."
            }
            # Accept either 'pwsh.exe' or 'powershell.exe'
            $exe = [System.IO.Path]::GetFileName($_).ToLower()
            if (($exe -ne "pwsh.exe") -and ($exe -ne "powershell.exe")) {
                throw "pwshPath '$_' is not 'pwsh.exe' or 'powershell.exe'."
            }
            $true
        })]
    [string]$pwshPath = $(
        $default = $null
        try {
            $default = (Get-Command pwsh.exe -ErrorAction Stop).Source
        }
        catch {
            try {
                $default = (Get-Command powershell.exe -ErrorAction Stop).Source
            }
            catch {}
        }
        $default
    ),

    # [ValidateNotNullOrEmpty()]
    # [ValidateScript({
    #         if (-not (Test-Path $_)) {
    #             throw "chezmoiPath '$_' does not exist."
    #         }
    #         if (-not (Test-Path $_ -PathType Leaf)) {
    #             throw "chezmoiPath '$_' is not a file."
    #         }
    #         if (-not ($_.ToLower().EndsWith('.exe'))) {
    #             throw "chezmoiPath '$_' does not appear to be an executable file."
    #         }
    #         $true
    #     })]
    # [string]$chezmoiPath = $( (Get-Command chezmoi -ErrorAction SilentlyContinue).Source ),

    # Install-only parameter
    [Parameter(ParameterSetName = "Install", Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[^\\/:*?"<>|]+$')]
    [string]$LogFileName = "sync-service.log"
)

# Parameter validation for Install mode (shared parameters need stricter validation)
if ($PSCmdlet.ParameterSetName -eq "Install") {
    # Create WrapperScriptDest if it doesn't exist (will be needed for the wrapper script)
    if (-not (Test-Path $WrapperScriptDest)) {
        try {
            New-Item -ItemType Directory -Path $WrapperScriptDest -Force | Out-Null
            Write-Verbose "Created WrapperScriptDest directory: $WrapperScriptDest"
        }
        catch {
            Write-Error "Failed to create WrapperScriptDest directory '$WrapperScriptDest': $_"
            exit 1
        }
    }
    if (-not (Test-Path $WrapperScriptDest -PathType Container)) {
        Write-Error "WrapperScriptDest '$WrapperScriptDest' exists but is not a directory. Please provide a directory path."
        exit 1
    }
    
    # Validate ServyModulePath exists for Install mode
    if (-not (Test-Path $ServyModulePath -PathType Leaf)) {
        Write-Error "ServyModulePath '$ServyModulePath' must be an existing '.psm1' file."
        exit 1
    }
    if ([System.IO.Path]::GetExtension($ServyModulePath).ToLower() -ne ".psm1") {
        Write-Error "ServyModulePath '$ServyModulePath' must be an existing '.psm1' file."
        exit 1
    }
    
    # Create InstallLogDir if it doesn't exist (will be needed for install logs)
    if (-not (Test-Path $InstallLogDir)) {
        try {
            New-Item -ItemType Directory -Path $InstallLogDir -Force | Out-Null
            Write-Verbose "Created InstallLogDir directory: $InstallLogDir"
        }
        catch {
            Write-Error "Failed to create InstallLogDir directory '$InstallLogDir': $_"
            exit 1
        }
    }
    if (-not (Test-Path $InstallLogDir -PathType Container)) {
        Write-Error "InstallLogDir '$InstallLogDir' exists but is not a directory. Please provide a directory path."
        exit 1
    }
    
    # Create ServiceDir if it doesn't exist (will be needed for service logs)
    if (-not (Test-Path $ServiceDir)) {
        try {
            New-Item -ItemType Directory -Path $ServiceDir -Force | Out-Null
            Write-Verbose "Created ServiceDir directory: $ServiceDir"
        }
        catch {
            Write-Error "Failed to create ServiceDir directory '$ServiceDir': $_"
            exit 1
        }
    }
    if (-not (Test-Path $ServiceDir -PathType Container)) {
        Write-Error "ServiceDir '$ServiceDir' exists but is not a directory. Please provide a directory path."
        exit 1
    }
}

# Log file paths (parameter dependent)
if ($PSCmdlet.ParameterSetName -eq "Install") {
    $ServiceLogDir = Join-Path $ServiceDir "logs"
    
    # Ensure ServiceLogDir exists
    if (-not (Test-Path $ServiceLogDir)) {
        try {
            New-Item -ItemType Directory -Path $ServiceLogDir -Force | Out-Null
            Write-Verbose "Created ServiceLogDir directory: $ServiceLogDir"
        }
        catch {
            Write-Error "Failed to create ServiceLogDir directory '$ServiceLogDir': $_"
            exit 1
        }
    }
    
    $serviceLogFile = Join-Path $ServiceLogDir $LogFileName
    $InstallLogFile = Join-Path $InstallLogDir "install.log"
    $stdoutLogFile = $serviceLogFile
    $stderrLogFile = $serviceLogFile
    $WrapperScriptDestFile = Join-Path $WrapperScriptDest (Split-Path $WrapperScriptSource -Leaf)
}
else {
    # Uninstall mode - create log directory if it doesn't exist
    if (-not (Test-Path $InstallLogDir)) {
        New-Item -ItemType Directory -Path $InstallLogDir -Force | Out-Null
    }
    $InstallLogFile = Join-Path $InstallLogDir "uninstall.log"
    $WrapperScriptDestFile = Join-Path $WrapperScriptDest "chezmoi-sync-service.ps1"
}


# Function to write log entries
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Ensure log directory exists
    $logDir = $InstallLogDir
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    Add-Content -Path $InstallLogFile -Value $logMessage

    # Color output based on level
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARN" { Write-Host $logMessage -ForegroundColor Yellow }
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
}
catch {
    Write-Log "Failed to check Administrator privileges: $_" "ERROR"
    exit 1
}

# Import Servy PowerShell Module
try {
    if (Test-Path $ServyModulePath) {
        Import-Module $ServyModulePath -Force
        Write-Log "Servy PowerShell module loaded successfully"
    }
    else {
        if ($PSCmdlet.ParameterSetName -eq "Install") {
            Write-Log "Servy module not found at $ServyModulePath" "ERROR"
            exit 1
        }
        else {
            Write-Log "Servy module not found at $ServyModulePath - will attempt standard removal" "WARN"
        }
    }
}
catch {
    if ($PSCmdlet.ParameterSetName -eq "Install") {
        Write-Log "Failed to load Servy module: $_" "ERROR"
        exit 1
    }
    else {
        Write-Log "Failed to load Servy module: $_" "WARN"
    }
}

# Get current user Credentials for the service (Install mode only)
if ($PSCmdlet.ParameterSetName -eq "Install") {
    if (-not $Credentials) {
        Write-Host "`nPlease enter your Windows password to configure the service account:" -ForegroundColor Cyan
        Write-Log "Service will run as current user: $env:USERNAME"
        $Credentials = Get-Credential -UserName "$env:USERDOMAIN\$env:USERNAME" -Message "Enter password for service account"
        if (-not $Credentials) {
            Write-Log "Credential input cancelled" "ERROR"
            exit 1
        }
    }
    Write-Log "Starting Chezmoi Sync Service installation..."
}
else {
    Write-Log "Starting Chezmoi Sync Service uninstallation..."
}

function Wait-ForPredicate {
    param (
        [Parameter(Mandatory)]
        [scriptblock]$Predicate,

        [Parameter(Mandatory = $false)]
        [double]$TimeoutSeconds = 2,

        [Parameter(Mandatory = $false)]
        [double]$IntervalSeconds = 0.2
    )

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        if (& $Predicate) {
            break
        }
        Start-Sleep -Seconds $IntervalSeconds
        $elapsed += $IntervalSeconds
    }
}

function Remove-ServyServiceAndWait {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )

    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $existingService) {
        return  # Nothing to remove
    }

    Write-Log "Service '$ServiceName' found. Stopping and removing..."

    # Try to use Servy if available
    $servyAvailable = Get-Command Uninstall-ServyService -ErrorAction SilentlyContinue
    
    try {
        if ($servyAvailable) {
            Write-Log "Using Servy to remove service..."
            
            # Stop the service
            Stop-ServyService -Quiet -Name $ServiceName

            # Wait for the service to stop
            Wait-ForPredicate -Predicate { 
                $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
                (-not $service) -or ($service.Status -eq 'Stopped')
            } -TimeoutSeconds 5 -IntervalSeconds 0.2

            Write-Log "Service stopped"

            # Remove the service
            Uninstall-ServyService -Quiet -Name $ServiceName

            # Wait for service removal confirmation
            Wait-ForPredicate -Predicate { -not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) } -TimeoutSeconds 5 -IntervalSeconds 0.2

            if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
                Write-Log "Warning: Service '$ServiceName' still exists after Servy removal." "WARN"
            }
            else {
                Write-Log "Service removed successfully using Servy"
            }
        }
        else {
            # Fallback to standard service removal
            Write-Log "Servy not available, using standard service removal..."
            
            # Refresh service status
            $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            
            # Stop the service if running
            if ($service -and $service.Status -eq 'Running') {
                Write-Log "Stopping service..."
                Stop-Service -Name $ServiceName -Force -ErrorAction Stop
                
                # Wait for service to stop
                Wait-ForPredicate -Predicate { 
                    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
                    (-not $svc) -or ($svc.Status -eq 'Stopped')
                } -TimeoutSeconds 5 -IntervalSeconds 0.2
                
                Write-Log "Service stopped successfully"
            }
            else {
                Write-Log "Service is already stopped or not found"
            }
            
            # Remove the service using sc.exe
            Write-Log "Removing service..."
            $result = sc.exe delete $ServiceName 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                # Wait for service to be fully removed
                Wait-ForPredicate -Predicate { 
                    -not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) 
                } -TimeoutSeconds 5 -IntervalSeconds 0.2
                
                if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
                    Write-Log "Warning: Service still exists after sc.exe delete" "WARN"
                }
                else {
                    Write-Log "Service removed successfully"
                }
            }
            else {
                Write-Log "Failed to remove service: $result" "ERROR"
                exit 1
            }
        }
    }
    catch {
        Write-Log "Error removing service: $_" "ERROR"
        Write-Log "Error details: $($_.Exception.Message)" "ERROR"
        exit 1
    }
}

function Start-ServyServiceAndWait {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )
    # Start the service
    try {
        Write-Log "Starting service..."

        Start-ServyService -Quiet -Name $ServiceName

        # Wait for the service to transition to 'Running' using Wait-ForPredicate (timeout: 8 seconds)
        Wait-ForPredicate -Predicate { 
            $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            $svc -and $svc.Status -eq 'Running'
        } -TimeoutSeconds 8 -IntervalSeconds 0.5

        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

        if ($service -and $service.Status -eq 'Running') {
            Write-Log "Service started successfully and is running" "SUCCESS"
        }
        elseif ($service) {
            Write-Log "Service status: $($service.Status)" "WARN"
        }
        else {
            Write-Log "Service not found after start attempt." "ERROR"
        }
    }
    catch {
        Write-Log "Failed to start service: $_" "ERROR"
        Write-Log "You can try starting it manually with: Start-Service -Name $ServiceName" "WARN"
    }
}

function Install-ServyServiceAndWait {
    param (
        [Parameter(Mandatory)]
        $WrapperScriptDest,

        [Parameter(Mandatory)]
        $WrapperScriptSource,

        [Parameter(Mandatory)]
        $WrapperScriptDestFile,

        [Parameter(Mandatory)]
        [PSCredential] $Credentials,

        [Parameter(Mandatory)]
        $ServiceName,

        [Parameter(Mandatory)]
        $ServiceDisplayName,

        [Parameter(Mandatory)]
        $ServiceDescription,

        [Parameter(Mandatory)]
        $pwshPath,

        [Parameter(Mandatory)]
        $stdoutLogFile,

        [Parameter(Mandatory)]
        $stderrLogFile
    )

    # Create the service using Servy
    try {

        # Copy wrapper script to destination directory as chezmoi-sync-service.ps1
        try {
            Copy-Item -Path $WrapperScriptSource -Destination $WrapperScriptDestFile -Force
            Write-Log "Wrapper script copied to: $WrapperScriptDestFile" "SUCCESS"
        }
        catch {
            if ($_.CategoryInfo.Activity -eq "Copy-Item" -and `
                    $_.CategoryInfo.Reason -eq "IOException" -and `
                    $_.Exception.Message -like "*Cannot overwrite the item with itself*") {
                Write-Log "Copy-Item warning ignored: $_" "WARN"
                # do not exit, treat as success
            }
            else {
                Write-Log "Failed to copy wrapper script: $_" "ERROR"
                exit 1
            }
        }

        Write-Log "Creating service using Servy..."

        $username = $Credentials.UserName
        $password = $Credentials.GetNetworkCredential().Password

        # Install the service using Servy PowerShell Module
        Install-ServyService `
            -Quiet `
            -Name $ServiceName `
            -DisplayName $ServiceDisplayName `
            -Description $ServiceDescription `
            -Path $pwshPath `
            -StartupDir $env:USERPROFILE `
            -Params "-NoProfile -ExecutionPolicy Bypass -File `"$WrapperScriptDestFile`"" `
            -StartupType "Automatic" `
            -Priority "Normal" `
            -Stdout "$stdoutLogFile" `
            -Stderr "$stderrLogFile" `
            -EnableSizeRotation `
            -RotationSize "10" `
            -MaxRotations "5" `
            -User $username `
            -Password $password

        # Wait for the service to appear in the service list (installed)
        Wait-ForPredicate -Predicate { Get-Service -Name $ServiceName -ErrorAction SilentlyContinue } -TimeoutSeconds 5 -IntervalSeconds 0.2

        # Confirm service object exists
        if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
            Write-Log "Service created successfully using Servy" "SUCCESS"
        }
        else {
            Write-Log "Service was not found after installation attempt." "ERROR"
            exit 1
        }
    }
    catch {
        Write-Log "Failed to create service: $_" "ERROR"
        Write-Log "Error details: $($_.Exception.Message)" "ERROR"
        exit 1
    }

}

# Main execution - branch based on parameter set
if ($PSCmdlet.ParameterSetName -eq "Uninstall") {
    # Uninstall mode - remove service and cleanup files
    
    # Remove the service
    Remove-ServyServiceAndWait -ServiceName $ServiceName
    
    # Clean up wrapper script
    if (Test-Path $WrapperScriptDestFile) {
        try {
            Write-Log "Removing wrapper script: $WrapperScriptDestFile"
            Remove-Item -Path $WrapperScriptDestFile -Force -ErrorAction Stop
            Write-Log "Wrapper script removed successfully" "SUCCESS"
        }
        catch {
            if ($_.Exception -is [System.IO.IOException] -and 
                $_.Exception.Message -like "*being used by another process*") {
                Write-Log "Wrapper script is in use, will be deleted on reboot" "WARN"
                Write-Log "You may need to manually delete: $WrapperScriptDestFile" "WARN"
            }
            else {
                Write-Log "Failed to remove wrapper script: $_" "ERROR"
                Write-Log "Error details: $($_.Exception.Message)" "ERROR"
                Write-Log "You may need to manually delete: $WrapperScriptDestFile" "WARN"
            }
        }
    }
    else {
        Write-Log "Wrapper script not found at: $WrapperScriptDestFile"
    }
    
    # Summary
    Write-Log "`nUninstallation completed!" "SUCCESS"
    Write-Log "Service '$ServiceName' has been removed from the system"
    Write-Log "`nNote: Log files have been preserved in: $InstallLogDir"
    Write-Log "You can manually delete these if no longer needed"
}
else {
    # Install mode - remove any existing service, then install new one
    Remove-ServyServiceAndWait -ServiceName $ServiceName
    
    Install-ServyServiceAndWait `
        -WrapperScriptDest $WrapperScriptDest `
        -WrapperScriptSource $WrapperScriptSource `
        -WrapperScriptDestFile $WrapperScriptDestFile `
        -Credentials $Credentials `
        -ServiceName $ServiceName `
        -ServiceDisplayName $ServiceDisplayName `
        -ServiceDescription $ServiceDescription `
        -pwshPath $pwshPath `
        -stdoutLogFile $stdoutLogFile `
        -stderrLogFile $stderrLogFile
    
    Start-ServyServiceAndWait -ServiceName $ServiceName

    # Display service information
    Write-Log "`nService installation completed!" "SUCCESS"
    Write-Log "Service Name: $ServiceName"
    Write-Log "Display Name: $ServiceDisplayName"
    Write-Log "Wrapper Script Directory: $WrapperScriptDest"
    Write-Log "Wrapper Script File: $WrapperScriptDestFile"
    Write-Log "Service Log File: $serviceLogFile"
    Write-Log "`nTo check service status: Get-Service -Name $ServiceName"
    Write-Log "To view service logs: Get-Content '$serviceLogFile' -Tail 20"
}
