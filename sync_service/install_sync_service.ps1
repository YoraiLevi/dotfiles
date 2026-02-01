<#
.SYNOPSIS
    Chezmoi Sync Service - Run, Install, or Uninstall

.DESCRIPTION
    A unified script that can run the chezmoi sync service, install it as a Windows Service, or uninstall it.
    
    Three modes of operation:
    - RUN MODE (default): Executes the service loop, running chezmoi sync every 5 minutes
    - INSTALL MODE: Installs the service as a Windows Service (requires Administrator privileges)
    - UNINSTALL MODE: Uninstalls the Windows Service (requires Administrator privileges)
    
    The service periodically runs chezmoi to apply dotfiles every 5 minutes.
    Installation and uninstallation prefer the Servy PowerShell module but can fall back to standard Windows service commands.
    Uninstallation preserves log files for troubleshooting.

.PARAMETER Install
    Switch to install the service. Requires Administrator privileges.

.PARAMETER Uninstall
    Switch to uninstall the service. Requires Administrator privileges.

.PARAMETER ServiceName
    The internal Windows service name (letters, numbers, underscore allowed).

.PARAMETER ServiceDisplayName
    The display name shown in Windows Services.

.PARAMETER ServiceDescription
    The Windows service description.

.PARAMETER ServiceScriptDest
    Directory where the service script will be copied during installation (Install mode only).

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
    # Run mode (default) - executes the service loop
    .\install_sync_service.ps1

.EXAMPLE
    # Install mode
    .\install_sync_service.ps1 -Install `
        -ServiceName "ChezmoiSync" `
        -ServiceDisplayName "Chezmoi Sync Service" `
        -Credentials (Get-Credential)

.EXAMPLE
    # Uninstall mode
    .\install_sync_service.ps1 -Uninstall -ServiceName "ChezmoiSync"
#>

[CmdletBinding(DefaultParameterSetName = "Run")]
param(
    # Install switch - installs the service as a Windows Service
    [Parameter(ParameterSetName = "Install", Mandatory = $true)]
    [switch]$Install,

    # Uninstall switch - uninstalls the service
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

    # Shared parameter (needed for both install and uninstall)
    # Note: Validation is relaxed for uninstall mode - handled in script body
    # This is where the script will be copied to when installing the service
    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Uninstall")]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceScriptDest = "$env:USERPROFILE\.local\bin",

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
    [string]$PwshPath = $(
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
        if (-not $default) {
            throw "Neither pwsh.exe nor powershell.exe found in PATH. Please install PowerShell or specify -pwshPath explicitly."
        }
        $default
    ),

    # Install-only parameter
    [Parameter(ParameterSetName = "Install", Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[^\\/:*?"<>|]+$')]
    [string]$LogFileName = "sync-service.log",

    # Install-only parameter for sync interval
    [Parameter(ParameterSetName = "Install")]
    [int]$SyncIntervalMinutes = 5
)

# ============================================================================
# FUNCTION DEFINITIONS
# ============================================================================

# Helper function to ensure directory exists
function Assert-DirectoryExists {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$Description
    )
    
    if (-not (Test-Path $Path)) {
        try {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Verbose "Created $Description directory: $Path"
        }
        catch {
            throw "Failed to create $Description directory '$Path': $_"
        }
    }
    
    if (-not (Test-Path $Path -PathType Container)) {
        throw "$Description '$Path' exists but is not a directory. Please provide a directory path."
    }
}

# Function to write log entries
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Ensure log directory exists (only on first call)
    if (-not $script:logDirCreated) {
        if (-not (Test-Path $InstallLogDir)) {
            New-Item -ItemType Directory -Path $InstallLogDir -Force | Out-Null
        }
        $script:logDirCreated = $true
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
            return $true
        }
        Start-Sleep -Seconds $IntervalSeconds
        $elapsed += $IntervalSeconds
    }
    return $false
}

# Function to show toast notifications (replaces GUI dialogs for service context)
function Show-ToastNotification {
    param(
        [string]$Title = "Chezmoi Sync Service",
        [string]$Message,
        [string]$LogFilePath
    )
    
    # Only works on Windows 10+
    if ([Environment]::OSVersion.Version.Major -ge 10) {
        $ToastXml = @"
<toast>
    <visual>
        <binding template="ToastGeneric">
            <text>$Title</text>
            <text>$Message</text>
            <text>Log: $LogFilePath</text>
        </binding>
    </visual>
</toast>
"@
        try {
            [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
            [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
            
            $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
            $xml.LoadXml($ToastXml)
            $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("ChezmoiSync").Show($toast)
        } catch {
            Write-Log "Failed to show toast notification: $_" "WARN"
        }
    }
}

# Function to rotate log files
function Rotate-LogFile {
    param(
        [string]$LogFilePath,
        [int]$MaxSizeMB = 10,
        [int]$MaxRotations = 5
    )
    
    if ((Test-Path $LogFilePath) -and ((Get-Item $LogFilePath).Length -gt ($MaxSizeMB * 1MB))) {
        # Rotate existing logs
        for ($i = $MaxRotations - 1; $i -gt 0; $i--) {
            $src = "$LogFilePath.$i"
            $dst = "$LogFilePath.$($i + 1)"
            if (Test-Path $src) {
                Move-Item $src $dst -Force
            }
        }
        Move-Item $LogFilePath "$LogFilePath.1" -Force
        Write-Log "Log file rotated" "INFO"
    }
}

# Function to save service configuration
function Save-ServiceConfig {
    param(
        [string]$ConfigPath,
        [string]$ChezmoiPath,
        [int]$SyncIntervalMinutes,
        [bool]$EnableReAdd = $true
    )
    
    $config = @{
        ChezmoiPath = $ChezmoiPath
        SyncIntervalMinutes = $SyncIntervalMinutes
        EnableReAdd = $EnableReAdd
        LogLevel = "INFO"
        MaxLogSizeMB = 10
        MaxLogRotations = 5
    }
    
    try {
        $configDir = Split-Path $ConfigPath -Parent
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
        
        $config | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
        Write-Log "Configuration saved to: $ConfigPath"
    }
    catch {
        Write-Log "Failed to save configuration: $_" "ERROR"
        throw
    }
}

# Function to load service configuration
function Get-ServiceConfig {
    param([string]$ConfigPath)
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Log "Configuration file not found at: $ConfigPath" "WARN"
        return $null
    }
    
    try {
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        Write-Log "Configuration loaded from: $ConfigPath"
        return $config
    }
    catch {
        Write-Log "Failed to load configuration: $_" "ERROR"
        return $null
    }
}

# Function to execute chezmoi command
function Invoke-ChezmoiSync {
    param(
        [string]$ChezmoiPath,
        [string]$ServiceLogFile
    )
    
    try {
        # Rotate log if needed
        Rotate-LogFile -LogFilePath $ServiceLogFile -MaxSizeMB 10 -MaxRotations 5
        
        Write-Log "Starting chezmoi sync..." "INFO"
        
        # Check if chezmoi.exe exists
        if (-not (Test-Path $ChezmoiPath)) {
            Write-Log "ERROR: chezmoi.exe not found at $ChezmoiPath" "ERROR"
            Write-Log "Skipping this sync cycle, will retry on next interval" "WARN"
            return
        }
        
        # Execute chezmoi re-add before update
        Write-Log "Running chezmoi re-add..." "INFO"
        & $ChezmoiPath re-add 2>&1 | Tee-Object -FilePath $ServiceLogFile -Append | Out-Null
        $reAddExitCode = $LASTEXITCODE

        if ($reAddExitCode -eq 0) {
            Write-Log "chezmoi re-add completed successfully" "INFO"
        }
        else {
            Write-Log "ERROR: chezmoi re-add failed with exit code $reAddExitCode" "ERROR"

            $message = @"
chezmoi re-add failed.
Please check your Chezmoi configuration or the sync log for details.

Chezmoi path: $ChezmoiPath
Log file: $ServiceLogFile
"@

            Show-ToastNotification -Message $message -LogFilePath $ServiceLogFile
            Write-Log "Skipping this sync cycle, will retry on next interval" "WARN"
            return
        }

        # Execute chezmoi update --init --apply --force
        $output = & $ChezmoiPath update --init --apply --force 2>&1 | Tee-Object -FilePath $ServiceLogFile -Append
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            Write-Log "Chezmoi sync completed successfully" "SUCCESS"
            if ($output) {
                # Write-Log "Output: $output" "INFO"
            }
        }
        else {
            Write-Log "ERROR: Chezmoi sync failed with exit code $exitCode" "ERROR"

            $message = @"
chezmoi update --init --apply --force failed.
Please check your Chezmoi configuration or the sync log for details.

Chezmoi path: $ChezmoiPath
Log file: $ServiceLogFile
"@

            Show-ToastNotification -Message $message -LogFilePath $ServiceLogFile
            Write-Log "Skipping this sync cycle, will retry on next interval" "WARN"
            return
        }

    }
    catch {
        Write-Log "ERROR: Exception during chezmoi sync - $_" "ERROR"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        Write-Log "Skipping this sync cycle, will retry on next interval" "WARN"
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
    $servyAvailable = $script:ServyAvailable
    
    try {
        if ($servyAvailable) {
            Write-Log "Using Servy to remove service..."
            
            # Stop the service
            Stop-ServyService -Quiet -Name $ServiceName

            # Wait for the service to stop
            $stopped = Wait-ForPredicate -Predicate { 
                $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
                (-not $service) -or ($service.Status -eq 'Stopped')
            } -TimeoutSeconds 5 -IntervalSeconds 0.2

            if ($stopped) {
                Write-Log "Service stopped"
            } else {
                Write-Log "Service stop timed out" "WARN"
            }

            # Remove the service
            Uninstall-ServyService -Quiet -Name $ServiceName

            # Wait for service removal confirmation
            $removed = Wait-ForPredicate -Predicate { -not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) } -TimeoutSeconds 5 -IntervalSeconds 0.2

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
                $stopped = Wait-ForPredicate -Predicate { 
                    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
                    (-not $svc) -or ($svc.Status -eq 'Stopped')
                } -TimeoutSeconds 5 -IntervalSeconds 0.2
                
                if ($stopped) {
                    Write-Log "Service stopped successfully"
                } else {
                    Write-Log "Service stop timed out" "WARN"
                }
            }
            else {
                Write-Log "Service is already stopped or not found"
            }
            
            # Remove the service using sc.exe
            Write-Log "Removing service..."
            $result = sc.exe delete $ServiceName 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                # Wait for service to be fully removed
                $removed = Wait-ForPredicate -Predicate { 
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
                throw "Failed to remove service: $result"
            }
        }
    }
    catch {
        Write-Log "Error removing service: $_" "ERROR"
        Write-Log "Error details: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Start-ServyServiceAndWait {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )
    
    try {
        Write-Log "Starting service..."

        # Try Servy first, fallback to standard Start-Service
        $servyAvailable = $script:ServyAvailable
        
        if ($servyAvailable) {
            Start-ServyService -Quiet -Name $ServiceName
        }
        else {
            Start-Service -Name $ServiceName -ErrorAction Stop
        }

        # Wait for the service to transition to 'Running' (timeout: 8 seconds)
        $running = Wait-ForPredicate -Predicate { 
            $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            $svc -and $svc.Status -eq 'Running'
        } -TimeoutSeconds 8 -IntervalSeconds 0.5

        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

        if ($service -and $service.Status -eq 'Running') {
            Write-Log "Service started successfully and is running" "SUCCESS"
        }
        elseif ($service) {
            Write-Log "Service status: $($service.Status)" "WARN"
            Write-Log "Service failed to reach Running state. You can try starting it manually with: Start-Service -Name $ServiceName" "WARN"
        }
        else {
            Write-Log "Service not found after start attempt." "ERROR"
            throw "Service '$ServiceName' not found after start attempt"
        }
    }
    catch {
        Write-Log "Failed to start service: $_" "ERROR"
        Write-Log "Error details: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Install-ServyServiceAndWait {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$ServiceScriptDestFile,

        [Parameter(Mandatory)]
        [PSCredential]$Credentials,

        [Parameter(Mandatory)]
        [string]$ServiceName,

        [Parameter(Mandatory)]
        [string]$ServiceDisplayName,

        [Parameter(Mandatory)]
        [string]$ServiceDescription,

        [Parameter(Mandatory)]
        [string]$PwshPath,

        [Parameter(Mandatory)]
        [string]$StdoutLogFile,

        [Parameter(Mandatory)]
        [string]$StderrLogFile
    )

    # Create the service using Servy
    try {

        # Copy this script with consistent name
        try {
            $currentScriptPath = $PSCommandPath
            Copy-Item -Path $currentScriptPath -Destination $ServiceScriptDestFile -Force
            
            # Verify copy succeeded
            if (-not (Test-Path $ServiceScriptDestFile)) {
                throw "Script copy verification failed - file not found at destination"
            }
            
            $srcSize = (Get-Item $currentScriptPath).Length
            $dstSize = (Get-Item $ServiceScriptDestFile).Length
            if ($srcSize -ne $dstSize) {
                throw "Script copy verification failed - file sizes don't match"
            }
            
            Write-Log "Service script copied and verified: $ServiceScriptDestFile" "SUCCESS"
        }
        catch {
            # Handle "cannot overwrite itself" gracefully
            if ($_.Exception.Message -like "*Cannot overwrite the item with itself*") {
                Write-Log "Script already at destination (same file)" "INFO"
            } else {
                Write-Log "Failed to copy service script: $_" "ERROR"
                throw
            }
        }

        Write-Log "Creating service using Servy..."

        # Use consistent credential format (full DOMAIN\User format for service)
        $username = $Credentials.UserName  # Full format: DOMAIN\User or MACHINE\User
        $password = $Credentials.GetNetworkCredential().Password
        
        Write-Log "Service will run as: $username"

        # Install the service using Servy PowerShell Module
        Install-ServyService `
            -Quiet `
            -Name $ServiceName `
            -DisplayName $ServiceDisplayName `
            -Description $ServiceDescription `
            -Path $PwshPath `
            -StartupDir $env:USERPROFILE `
            -Params "-NoProfile -ExecutionPolicy Bypass -File `"$ServiceScriptDestFile`"" `
            -StartupType "Automatic" `
            -Priority "Normal" `
            -Stdout "$StdoutLogFile" `
            -Stderr "$StderrLogFile" `
            -User $username `
            -Password $password

        # Wait for the service to appear in the service list (installed)
        $created = Wait-ForPredicate -Predicate { Get-Service -Name $ServiceName -ErrorAction SilentlyContinue } -TimeoutSeconds 5 -IntervalSeconds 0.2

        # Confirm service object exists
        if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
            Write-Log "Service created successfully using Servy" "SUCCESS"
        }
        else {
            Write-Log "Service was not found after installation attempt." "ERROR"
            throw "Service '$ServiceName' was not found after installation attempt"
        }
    }
    catch {
        Write-Log "Failed to create service: $_" "ERROR"
        Write-Log "Error details: $($_.Exception.Message)" "ERROR"
        
        # Cleanup on failure - remove the copied service script
        if (Test-Path $ServiceScriptDestFile) {
            try {
                Remove-Item -Path $ServiceScriptDestFile -Force -ErrorAction SilentlyContinue
                Write-Log "Cleaned up service script after failed installation" "INFO"
            }
            catch {
                Write-Log "Failed to cleanup service script: $_" "WARN"
            }
        }
        
        throw
    }
}

# ============================================================================
# PARAMETER VALIDATION AND INITIALIZATION
# ============================================================================

# Parameter validation for Install mode (shared parameters need stricter validation)
if ($PSCmdlet.ParameterSetName -eq "Install") {
    # Ensure required directories exist
    try {
        Assert-DirectoryExists -Path $ServiceScriptDest -Description "ServiceScriptDest"
        Assert-DirectoryExists -Path $InstallLogDir -Description "InstallLogDir"
        Assert-DirectoryExists -Path $ServiceDir -Description "ServiceDir"
    }
    catch {
        Write-Error $_
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
}

# Log file paths (parameter dependent)
if ($PSCmdlet.ParameterSetName -eq "Install") {
    $ServiceLogDir = Join-Path $ServiceDir "logs"
    
    # Ensure ServiceLogDir exists
    try {
        Assert-DirectoryExists -Path $ServiceLogDir -Description "ServiceLogDir"
    }
    catch {
        Write-Error $_
        exit 1
    }
    
    $ServiceLogFile = Join-Path $ServiceLogDir $LogFileName
    $InstallLogFile = Join-Path $InstallLogDir "install.log"
    $StdoutLogFile = $ServiceLogFile
    $StderrLogFile = $ServiceLogFile
    $ServiceScriptDestFile = Join-Path $ServiceScriptDest "chezmoi-sync-service.ps1"
}
elseif ($PSCmdlet.ParameterSetName -eq "Uninstall") {
    # Uninstall mode - create log directory if it doesn't exist
    if (-not (Test-Path $InstallLogDir)) {
        New-Item -ItemType Directory -Path $InstallLogDir -Force | Out-Null
    }
    $InstallLogFile = Join-Path $InstallLogDir "uninstall.log"
    # Use the same default filename as Install mode for consistency
    $ServiceScriptDestFile = Join-Path $ServiceScriptDest "chezmoi-sync-service.ps1"
}

# ============================================================================
# MAIN EXECUTION LOGIC
# ============================================================================

# Check if running as Administrator (only for Install/Uninstall modes)
if ($PSCmdlet.ParameterSetName -eq "Install" -or $PSCmdlet.ParameterSetName -eq "Uninstall") {
    try {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $isAdmin) {
            Write-Log "This script requires Administrator privileges for Install/Uninstall operations. Please run as Administrator." "ERROR"
            exit 1
        }
    }
    catch {
        Write-Log "Failed to check Administrator privileges: $_" "ERROR"
        exit 1
    }
}

# Import Servy PowerShell Module
$script:ServyAvailable = $false

try {
    if (Test-Path $ServyModulePath) {
        Import-Module $ServyModulePath -Force
        $script:ServyAvailable = $true
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
    # Validate chezmoi exists and get absolute path
    try {
        $ChezmoiPath = (Get-Command chezmoi -ErrorAction Stop).Source
        Write-Log "Found chezmoi at: $ChezmoiPath"
    } catch {
        Write-Log "chezmoi.exe not found in PATH. Please install chezmoi first." "ERROR"
        Write-Log "Visit https://www.chezmoi.io/install/ for installation instructions." "ERROR"
        exit 1
    }
    
    if (-not $Credentials) {
        Write-Host "`nPlease enter your Windows password to configure the service account:" -ForegroundColor Cyan
        Write-Log "Service will run as current user: $env:USERNAME"
        
        # Get current user in proper format
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $defaultUsername = $currentUser.Name  # Already in DOMAIN\User or MACHINE\User format
        
        $Credentials = Get-Credential -UserName $defaultUsername -Message "Enter password for service account"
        if (-not $Credentials) {
            Write-Log "Credential input cancelled" "ERROR"
            exit 1
        }
    }
    
    # Validate credentials
    try {
        $netCred = $Credentials.GetNetworkCredential()
        $credUser = $netCred.UserName
        $credPass = $netCred.Password
        $credDomain = $netCred.Domain
        
        # Use the same format that will be used for service installation
        $serviceUsername = $Credentials.UserName  # Full format (DOMAIN\User or MACHINE\User)
        
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement
        $contextType = if ($credDomain) { 'Domain' } else { 'Machine' }
        $context = if ($credDomain) { $credDomain } else { $env:COMPUTERNAME }
        $pc = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($contextType, $context)
        
        if (-not $pc.ValidateCredentials($credUser, $credPass)) {
            Write-Log "Invalid credentials provided. Please check username and password." "ERROR"
            exit 1
        }
        Write-Log "Credentials validated successfully for user: $serviceUsername"
    }
    catch {
        Write-Log "Warning: Could not validate credentials: $_" "WARN"
        Write-Log "Service installation will continue, but service may fail to start if credentials are incorrect." "WARN"
    }
    
    Write-Log "Starting Chezmoi Sync Service installation..."
}
else {
    Write-Log "Starting Chezmoi Sync Service uninstallation..."
}

# ============================================================================
# MAIN EXECUTION - branch based on parameter set
# ============================================================================

if ($PSCmdlet.ParameterSetName -eq "Run") {
    # ========================================================================
    # RUN MODE - Execute the service loop
    # ========================================================================
    
    # Initialize logging FIRST (before any Write-Log calls)
    $ServiceLogDir = "$env:USERPROFILE\.local\share\chezmoi-sync\logs"
    $ServiceLogFile = Join-Path $ServiceLogDir "sync-service.log"
    
    # Ensure log directory exists
    if (-not (Test-Path $ServiceLogDir)) {
        try {
            New-Item -ItemType Directory -Path $ServiceLogDir -Force | Out-Null
        }
        catch {
            throw
        }
    }
    
    # Set the log file for Write-Log function BEFORE calling anything that logs
    $script:InstallLogFile = $ServiceLogFile
    
    # Load configuration (can now safely call Write-Log)
    $ConfigPath = "$env:USERPROFILE\.local\share\chezmoi-sync\config.json"
    $config = Get-ServiceConfig -ConfigPath $ConfigPath
    
    # Service configuration - use config if available, otherwise defaults
    if ($config) {
        $ChezmoiPath = $config.ChezmoiPath
        $IntervalSeconds = $config.SyncIntervalMinutes * 60
        Write-Log "Using configuration from: $ConfigPath"
    } else {
        # Fallback to defaults if config not found
        Write-Log "Configuration not found, using defaults" "WARN"
        try {
            $ChezmoiPath = (Get-Command chezmoi -ErrorAction Stop).Source
        } catch {
            Write-Log "FATAL: chezmoi.exe not found in PATH and no configuration file exists" "ERROR"
            exit 1
        }
        $IntervalSeconds = 5 * 60  # 5 minutes default
    }
    
    # Graceful shutdown flag
    $script:shouldStop = $false
    
    # Register shutdown handler
    $null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
        $script:shouldStop = $true
        Write-Log "Shutdown signal received" "INFO"
    }
    
    # Main service loop
    Write-Log "Chezmoi Sync Service started" "INFO"
    Write-Log "Chezmoi path: $ChezmoiPath" "INFO"
    Write-Log "Sync interval: $IntervalSeconds seconds" "INFO"
    
    try {
        while (-not $script:shouldStop) {
            Invoke-ChezmoiSync -ChezmoiPath $ChezmoiPath -ServiceLogFile $ServiceLogFile
            
            # Wait with cancellation check
            Write-Log "Waiting $IntervalSeconds seconds until next sync..." "INFO"
            $waited = 0
            while ((-not $script:shouldStop) -and ($waited -lt $IntervalSeconds)) {
                Start-Sleep -Seconds 1
                $waited++
            }
        }
    }
    catch {
        Write-Log "FATAL: Service loop terminated - $_" "ERROR"
        throw
    }
    finally {
        Write-Log "Chezmoi Sync Service stopped gracefully" "INFO"
    }
}
elseif ($PSCmdlet.ParameterSetName -eq "Uninstall") {
    # Uninstall mode - remove service and cleanup files
    try {
        # Remove the service
        Remove-ServyServiceAndWait -ServiceName $ServiceName
        
        # Clean up service script
        if (Test-Path $ServiceScriptDestFile) {
            try {
                Write-Log "Removing service script: $ServiceScriptDestFile"
                Remove-Item -Path $ServiceScriptDestFile -Force -ErrorAction Stop
                Write-Log "Service script removed successfully" "SUCCESS"
            }
            catch {
                if ($_.Exception -is [System.IO.IOException] -and 
                    $_.Exception.Message -like "*being used by another process*") {
                    Write-Log "Service script is in use, will be deleted on reboot" "WARN"
                    Write-Log "You may need to manually delete: $ServiceScriptDestFile" "WARN"
                }
                else {
                    Write-Log "Failed to remove service script: $_" "ERROR"
                    Write-Log "Error details: $($_.Exception.Message)" "ERROR"
                    Write-Log "You may need to manually delete: $ServiceScriptDestFile" "WARN"
                }
            }
        }
        else {
            Write-Log "Service script not found at: $ServiceScriptDestFile"
        }
        
        # Summary
        Write-Log "`nUninstallation completed!" "SUCCESS"
        Write-Log "Service '$ServiceName' has been removed from the system"
        Write-Log "`nNote: Log files have been preserved in: $InstallLogDir"
        Write-Log "You can manually delete these if no longer needed"
    }
    catch {
        Write-Log "Uninstallation failed: $_" "ERROR"
        exit 1
    }
}
elseif ($PSCmdlet.ParameterSetName -eq "Install") {
    # Install mode - remove any existing service, then install new one
    $serviceCreated = $false
    $scriptCopied = $false
    $configCreated = $false
    
    try {
        # Remove any existing service first
        Remove-ServyServiceAndWait -ServiceName $ServiceName
        
        # Create configuration file
        $ConfigPath = Join-Path $ServiceDir "config.json"
        Save-ServiceConfig `
            -ConfigPath $ConfigPath `
            -ChezmoiPath $ChezmoiPath `
            -SyncIntervalMinutes $SyncIntervalMinutes `
            -EnableReAdd $true
        $configCreated = $true
        
        Install-ServyServiceAndWait `
            -ServiceScriptDestFile $ServiceScriptDestFile `
            -Credentials $Credentials `
            -ServiceName $ServiceName `
            -ServiceDisplayName $ServiceDisplayName `
            -ServiceDescription $ServiceDescription `
            -PwshPath $PwshPath `
            -StdoutLogFile $StdoutLogFile `
            -StderrLogFile $StderrLogFile
        $serviceCreated = $true
        
        Start-ServyServiceAndWait -ServiceName $ServiceName

        # Display service information
        Write-Log "`nService installation completed!" "SUCCESS"
        Write-Log "Service Name: $ServiceName"
        Write-Log "Display Name: $ServiceDisplayName"
        Write-Log "Service Script Directory: $ServiceScriptDest"
        Write-Log "Service Script File: $ServiceScriptDestFile"
        Write-Log "Service Log File: $ServiceLogFile"
        Write-Log "Config File: $ConfigPath"
        Write-Log "`nTo check service status: Get-Service -Name $ServiceName"
        Write-Log "To view service logs: Get-Content '$ServiceLogFile' -Tail 20"
    }
    catch {
        Write-Log "Installation failed: $_" "ERROR"
        
        # Rollback on failure
        if ($serviceCreated) {
            try {
                Write-Log "Rolling back service installation..." "WARN"
                Remove-ServyServiceAndWait -ServiceName $ServiceName
                Write-Log "Service rollback completed" "INFO"
            }
            catch {
                Write-Log "Failed to rollback service: $_" "WARN"
            }
        }
        
        if ($scriptCopied -and (Test-Path $ServiceScriptDestFile)) {
            try {
                Remove-Item -Path $ServiceScriptDestFile -Force
                Write-Log "Script rollback completed" "INFO"
            }
            catch {
                Write-Log "Failed to rollback script: $_" "WARN"
            }
        }
        
        if ($configCreated -and (Test-Path $ConfigPath)) {
            try {
                Remove-Item -Path $ConfigPath -Force
                Write-Log "Config rollback completed" "INFO"
            }
            catch {
                Write-Log "Failed to rollback config: $_" "WARN"
            }
        }
        
        exit 1
    }
}
else {
    Write-Log "INTERNAL ERROR: Unknown parameter set '$($PSCmdlet.ParameterSetName)'. This should never happen." "ERROR"
    exit 1
}