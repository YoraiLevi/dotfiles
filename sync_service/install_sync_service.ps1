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
    [string]$LogFileName = "sync-service.log"
)

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
    
    $serviceLogFile = Join-Path $ServiceLogDir $LogFileName
    $InstallLogFile = Join-Path $InstallLogDir "install.log"
    $StdoutLogFile = $serviceLogFile
    $StderrLogFile = $serviceLogFile
    $WrapperScriptDestFile = Join-Path $WrapperScriptDest (Split-Path $WrapperScriptSource -Leaf)
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

# ============================================================================
# SERVICE-SPECIFIC FUNCTIONS (Run mode only)
# ============================================================================

# Function to show custom error dialog
function Show-ErrorDialog {
    param(
        [string]$Message,
        [string]$LogFilePath
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    # Create the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Chezmoi Sync Service Error"
    $form.Size = New-Object System.Drawing.Size(500, 280)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    
    # Error icon (PictureBox)
    $iconBox = New-Object System.Windows.Forms.PictureBox
    $iconBox.Location = New-Object System.Drawing.Point(20, 20)
    $iconBox.Size = New-Object System.Drawing.Size(32, 32)
    $iconBox.Image = [System.Drawing.SystemIcons]::Error.ToBitmap()
    $form.Controls.Add($iconBox)
    
    # Message label
    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(65, 20)
    $label.Size = New-Object System.Drawing.Size(400, 160)
    $label.Text = $Message
    $label.AutoSize = $false
    $form.Controls.Add($label)
    
    # Button panel for layout
    $buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonPanel.FlowDirection = "LeftToRight"
    $buttonPanel.Location = New-Object System.Drawing.Point(20, 190)
    $buttonPanel.Size = New-Object System.Drawing.Size(450, 40)
    $buttonPanel.Anchor = "Bottom"
    $buttonPanel.WrapContents = $false
    
    # Open Log button
    $btnOpenLog = New-Object System.Windows.Forms.Button
    $btnOpenLog.Size = New-Object System.Drawing.Size(120, 30)
    $btnOpenLog.Text = "Open Log"
    $btnOpenLog.DialogResult = [System.Windows.Forms.DialogResult]::Yes
    $buttonPanel.Controls.Add($btnOpenLog)
    
    # Copy Path button
    $btnCopyPath = New-Object System.Windows.Forms.Button
    $btnCopyPath.Size = New-Object System.Drawing.Size(120, 30)
    $btnCopyPath.Text = "Copy Path"
    $btnCopyPath.DialogResult = [System.Windows.Forms.DialogResult]::No
    $buttonPanel.Controls.Add($btnCopyPath)
    
    # OK button
    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Size = New-Object System.Drawing.Size(120, 30)
    $btnOK.Text = "OK"
    $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $buttonPanel.Controls.Add($btnOK)
    
    $form.Controls.Add($buttonPanel)
    $form.AcceptButton = $btnOK
    
    # Show dialog and handle result internally
    $result = $form.ShowDialog()
    
    switch ($result) {
        ([System.Windows.Forms.DialogResult]::Yes) {
            # Open Log button clicked
            try {
                if (Test-Path $LogFilePath) {
                    & $LogFilePath
                }
            }
            catch {
                Write-Log "Unable to open log file automatically: $_" "ERROR"
            }
        }
        ([System.Windows.Forms.DialogResult]::No) {
            # Copy Path button clicked
            try {
                $LogFilePath | Set-Clipboard
                Write-Log "Log file path copied to clipboard" "INFO"
                [System.Windows.Forms.MessageBox]::Show(
                    "Log file path copied to clipboard:`n$LogFilePath",
                    "Copied!",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            }
            catch {
                Write-Log "Failed to copy log file path to clipboard: $_" "ERROR"
            }
        }
    }
    # OK or X button: do nothing
}

# Function to execute chezmoi command
function Invoke-ChezmoiSync {
    param(
        [string]$ChezmoiPath,
        [string]$ServiceLogFile
    )
    
    try {
        Write-Log "Starting chezmoi sync..." "INFO"
        
        # Check if chezmoi.exe exists
        if (-not (Test-Path $ChezmoiPath)) {
            Write-Log "ERROR: chezmoi.exe not found at $ChezmoiPath" "ERROR"
            return
        }
        
        # Execute chezmoi re-add before init --apply
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

            Show-ErrorDialog -Message $message -LogFilePath $ServiceLogFile
            exit 1
        }

        # Execute chezmoi init --apply
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
chezmoi init --apply failed.
Please check your Chezmoi configuration or the sync log for details.

Chezmoi path: $ChezmoiPath
Log file: $ServiceLogFile
"@

            Show-ErrorDialog -Message $message -LogFilePath $ServiceLogFile
        }
        exit 1

    }
    catch {
        Write-Log "ERROR: Exception during chezmoi sync - $_" "ERROR"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    }
}

# ============================================================================
# INSTALL/UNINSTALL FUNCTIONS
# ============================================================================

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
        $servyAvailable = Get-Command Start-ServyService -ErrorAction SilentlyContinue
        
        if ($servyAvailable) {
            Start-ServyService -Quiet -Name $ServiceName
        }
        else {
            Start-Service -Name $ServiceName -ErrorAction Stop
        }

        # Wait for the service to transition to 'Running' (timeout: 8 seconds)
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

        # Copy this script itself to destination directory
        try {
            $currentScriptPath = $PSCommandPath
            Copy-Item -Path $currentScriptPath -Destination $ServiceScriptDestFile -Force
            Write-Log "Service script copied to: $ServiceScriptDestFile" "SUCCESS"
        }
        catch {
            if ($_.CategoryInfo.Activity -eq "Copy-Item" -and `
                    $_.CategoryInfo.Reason -eq "IOException" -and `
                    $_.Exception.Message -like "*Cannot overwrite the item with itself*") {
                Write-Log "Copy-Item warning ignored: $_" "WARN"
                # do not throw, treat as success
            }
            else {
                Write-Log "Failed to copy service script: $_" "ERROR"
                throw
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
            -Path $PwshPath `
            -StartupDir $env:USERPROFILE `
            -Params "-NoProfile -ExecutionPolicy Bypass -File `"$WrapperScriptDestFile`"" `
            -StartupType "Automatic" `
            -Priority "Normal" `
            -Stdout "$StdoutLogFile" `
            -Stderr "$StderrLogFile" `
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
# MAIN EXECUTION - branch based on parameter set
# ============================================================================

if ($PSCmdlet.ParameterSetName -eq "Run") {
    # ========================================================================
    # RUN MODE - Execute the service loop
    # ========================================================================
    
    # Service configuration
    $ChezmoiPath = (Get-Command chezmoi).Source
    $ServiceLogDir = "$env:USERPROFILE\.local\share\chezmoi-sync\logs"
    $ServiceLogFile = Join-Path $ServiceLogDir "sync-service.log"
    $IntervalSeconds = 5 * 60  # 5 minutes
    
    # Ensure log directory exists
    if (-not (Test-Path $ServiceLogDir)) {
        try {
            New-Item -ItemType Directory -Path $ServiceLogDir -Force | Out-Null
        }
        catch {
            throw
        }
    }
    
    # Override the InstallLogFile for Run mode to use the service log
    $script:InstallLogFile = $ServiceLogFile
    
    # Main service loop
    Write-Log "Chezmoi Sync Service started" "INFO"
    Write-Log "Chezmoi path: $ChezmoiPath" "INFO"
    Write-Log "Sync interval: $IntervalSeconds seconds" "INFO"
    
    try {
        while ($true) {
            Invoke-ChezmoiSync -ChezmoiPath $ChezmoiPath -ServiceLogFile $ServiceLogFile
            
            Write-Log "Waiting $IntervalSeconds seconds until next sync..." "INFO"
            Start-Sleep -Seconds $IntervalSeconds
        }
    }
    catch {
        Write-Log "FATAL: Service loop terminated - $_" "ERROR"
        throw
    }
    finally {
        Write-Log "Chezmoi Sync Service stopped" "INFO"
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
    try {
        Remove-ServyServiceAndWait -ServiceName $ServiceName
        
        Install-ServyServiceAndWait `
            -ServiceScriptDestFile $ServiceScriptDestFile `
            -Credentials $Credentials `
            -ServiceName $ServiceName `
            -ServiceDisplayName $ServiceDisplayName `
            -ServiceDescription $ServiceDescription `
            -pwshPath $PwshPath `
            -stdoutLogFile $StdoutLogFile `
            -stderrLogFile $StderrLogFile
        
        Start-ServyServiceAndWait -ServiceName $ServiceName

        # Display service information
        Write-Log "`nService installation completed!" "SUCCESS"
        Write-Log "Service Name: $ServiceName"
        Write-Log "Display Name: $ServiceDisplayName"
        Write-Log "Service Script Directory: $ServiceScriptDest"
        Write-Log "Service Script File: $ServiceScriptDestFile"
        Write-Log "Service Log File: $serviceLogFile"
        Write-Log "`nTo check service status: Get-Service -Name $ServiceName"
        Write-Log "To view service logs: Get-Content '$serviceLogFile' -Tail 20"
    }
    catch {
        Write-Log "Installation failed: $_" "ERROR"
        exit 1
    }
}
else {
    Write-Log "Unknown parameter set '$($PSCmdlet.ParameterSetName)'. Only 'Install' and 'Uninstall' are supported." "ERROR"
    exit 1
}