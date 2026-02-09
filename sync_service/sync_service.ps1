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
    
    [Parameter(ParameterSetName = "Run")]
    [Parameter(ParameterSetName = "RunLoop")]
    [switch]$Run,
    [Parameter(ParameterSetName = "RunLoop")]
    [switch]$Loop,
    
    # Shared parameters (both Install and Uninstall)
    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Uninstall")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern("^[a-zA-Z0-9_-]+$")] # Allow only alphanumerics + underscore + hyphen for service name
    [string]$ServiceName = "ChezmoiSync",

    # Install-only parameters
    [Parameter(ParameterSetName = "Install")]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceDisplayName = "Chezmoi Sync Service",

    [Parameter(ParameterSetName = "Install")]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceDescription = "Automatically syncs chezmoi dotfiles every 5 minutes by running 'chezmoi init --apply'",

    # Shared parameter (needed for both install and uninstall)
    [Parameter(ParameterSetName = "Install")]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceDir = $(
        # Determine chezmoi source directory by running 'chezmoi source-path'
        $default = "$env:USERPROFILE\.local\share\chezmoi-sync\"
        try {
            $chezmoiSourcePath = (& chezmoi source-path) 2>$null
            if ($null -ne $chezmoiSourcePath -and $chezmoiSourcePath.Trim() -ne "") {
                $currentDir = [System.IO.Path]::GetFullPath($PWD.ProviderPath)
                $sourceDir = [System.IO.Path]::GetFullPath($chezmoiSourcePath.Trim())
                if ($currentDir.ToLower().StartsWith($sourceDir.ToLower())) {
                    # Current directory is inside source path, use script's path
                    Split-Path -Parent $MyInvocation.MyCommand.Path
                }
                else {
                    $default
                }
            }
            else {
                $default
            }
        }
        catch {
            $default
        }
    ),

    # Shared parameter (needed for both install and uninstall)
    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Uninstall")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
            if (-not (Test-Path $_ -PathType Leaf)) {
                throw "ServyModulePath '$_' must be an existing '.psm1' file."
            }
            if ([System.IO.Path]::GetExtension($_).ToLower() -ne ".psm1") {
                throw "ServyModulePath '$_' must be an existing '.psm1' file."
            }
            $true
        })]
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
    [Parameter(ParameterSetName = "Install", Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credentials,

    # Install-only parameter
    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "RunLoop")]
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
    [Parameter(ParameterSetName = "Install")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[^\\/:*?"<>|]+$')]
    [string]$LogFileName = "sync-service.log",

    # Install-only parameter for sync interval
    [Parameter(ParameterSetName = "Install")]
    [int]$SyncIntervalMinutes = 5,

    [Parameter(ParameterSetName = "Install")]
    [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
    [string]$LogLevel = "INFO"
)

# ============================================================================
# FUNCTION DEFINITIONS
# ============================================================================

$VERSION = "v20260209"
$ConfigFileName = "config.json"

# Function to write log entries, now supports pipeline input for $Message
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [string]$Message,

        [Parameter(Position = 1)]
        [string]$Level = "INFO"
    )

    begin {
        # Define log level priorities
        $levelPriority = @{
            "ERROR"   = 3
            "WARN"    = 2
            "SUCCESS" = 1
            "INFO"    = 0
            "ALWAYS"  = 100 # Always log this message
        }
        # Get effective log level (script:LogLevel or fallback to INFO)
        $configuredLevel = $script:LogLevel
        if (-not $configuredLevel) { $configuredLevel = "INFO" }
        $configuredPriority = $levelPriority[$configuredLevel]
        if ($null -eq $configuredPriority) { $configuredPriority = 0 } # Default to INFO if unknown
    }

    process {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$timestamp] [$Level] $Message"

        # Actual message level priority
        $messagePriority = $levelPriority[$Level]
        if ($null -eq $messagePriority) { $messagePriority = 0 } # Default to INFO if unknown

        # Only log if message level >= configured level
        if ($messagePriority -ge $configuredPriority) {
            switch ($Level) {
                "ERROR" { Write-Host $logMessage -ForegroundColor Red }
                "WARN" { Write-Host $logMessage -ForegroundColor Yellow }
                "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
                default { Write-Host $logMessage }
            }
        }
    }
}
# Helper function to ensure directory exists

function Assert-CreateDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Path
        
    )
    
    if (-not (Test-Path $Path)) {
        try {
            New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
            Write-Log "Created directory: $Path"
        }
        catch {
            Write-Log "Failed to create directory '$Path': $_" "ERROR"
            throw $_
        }
    }
    
    if (-not (Test-Path $Path -PathType Container)) {
        $message = "'$Path' exists but is not a directory. Please provide a directory path."
        Write-Log $message "ERROR"
        throw $message
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

# Function to check if Servy module is available
function Test-ServyAvailable {
    param(
        [Parameter(Mandatory)]
        [string]$ServyModulePath
    )

    if (Test-Path $ServyModulePath) {
        Import-Module $ServyModulePath -Force -ErrorAction Stop
        Write-Log "Servy PowerShell module loaded successfully"
        try {
            $null = Get-Command -Name Install-ServyService -ErrorAction Stop
            $null = Get-Command -Name Uninstall-ServyService -ErrorAction Stop
            $null = Get-Command -Name Start-ServyService -ErrorAction Stop
            $null = Get-Command -Name Stop-ServyService -ErrorAction Stop
        }
        catch {
            Write-Log "Servy commands not found in module" "ERROR"
            return $false
        }
    }
    else {
        Write-Log "Servy module not found at $ServyModulePath" "ERROR"
        return $false
    }

    return $true
}

# Function to show toast notifications (replaces GUI dialogs for service context)
function Show-ToastNotification {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $true)]
        [string]$LogFilePath,
        [Parameter(Mandatory = $false)]
        [string]$Title = "Chezmoi Sync Service"
    )
    
    # Only works on Windows 10+
    if ([Environment]::OSVersion.Version.Major -lt 10) {
        return
    }
    # Try using BurntToast module first (if available)
    if (Get-Module -ListAvailable -Name BurntToast) {
        try {
            Import-Module BurntToast -ErrorAction Stop
            $btn = New-BTButton -Content "View Log" -Arguments $((Resolve-Path $LogFilePath).Path)
            New-BurntToastNotification -Text $Title, $Message `
                -AppLogo $null `
                -ExpirationTime $((Get-Date).AddHours(8)) `
                -Silent `
                -Urgent `
                -Button $btn `
                -ErrorAction Stop
            return
        }
        catch {
            Write-Log "Failed to show toast notification: $_" "WARN"
        }
    }
}

# Function to save service configuration
function Get-DefaultServiceConfig {
    return @{
        ChezmoiPath         = $null
        SyncIntervalMinutes = 5
        EnableReAdd         = $true
        LogLevel            = "INFO"
    }
}

function Save-ServiceConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true)]
        [string]$ChezmoiPath,

        [Parameter(Mandatory = $false)]
        $SyncIntervalMinutes = $null,

        [Parameter(Mandatory = $false)]
        $EnableReAdd = $null,

        [Parameter(Mandatory = $false)]
        $LogLevel = $null
    )
    
    $config = Get-DefaultServiceConfig
    $config.ChezmoiPath = $ChezmoiPath

    if ($null -ne $SyncIntervalMinutes) {
        $config.SyncIntervalMinutes = $SyncIntervalMinutes
    }
    if ($null -ne $EnableReAdd) {
        $config.EnableReAdd = $EnableReAdd
    }
    if ($null -ne $LogLevel) {
        $config.LogLevel = $LogLevel
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
        $fileData = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        Write-Log "Configuration loaded from: $ConfigPath"
        
        # Load defaults, then overlay file fields
        $defaults = Get-DefaultServiceConfig
        $merged = $defaults.Clone()
        foreach ($prop in $fileData.PSObject.Properties) {
            $merged[$prop.Name] = $fileData.$($prop.Name)
        }
        return $merged
    }
    catch {
        Write-Log "Failed to load configuration: $_" "ERROR"
        return $null
    }
}


# Function to execute chezmoi command
function Invoke-ChezmoiSync {
    param(
        [string]$ChezmoiPath
    )
    
    try {
        Write-Log "Starting chezmoi sync..." "INFO"
        
        # Check if chezmoi.exe exists
        if (-not (Test-Path $ChezmoiPath -ErrorAction Stop)) {
            Write-Log "ERROR: chezmoi.exe not found at $ChezmoiPath" "ERROR"
        }
        $null = choco export "$(Join-Path $ENV:USERPROFILE ".choco" "packages.config")"
        $null = @('cursor', 'code-insiders') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1 | ForEach-Object { & $_ --list-extensions | Out-File $(Join-Path $ENV:USERPROFILE ".vscode" "$_-extensions.txt") }
        $null = (Get-InstalledModule).Name | Out-File $(Join-Path $ENV:USERPROFILE ".powershell" "pwsh-modules.txt")
        # Execute chezmoi re-add before update
        Write-Log "Running chezmoi re-add..." "INFO"
        & $ChezmoiPath re-add 2>&1 | Out-String | Write-Log
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
"@

            Write-Log "Skipping this sync cycle, will retry on next interval" "WARN"
            throw "chezmoi re-add failed with exit code $reAddExitCode"
        }
        $Chezmoi_diff = $(& $ChezmoiPath git pull -- --autostash --rebase) | Out-String
        $NoChanges = 'Current branch master is up to date.', 'Already up to date.'
        $forceUpdate = ($(try { Get-Date -Date (Get-Content "$PSScriptRoot/date.tmp" -ErrorAction SilentlyContinue) }catch {}) -lt $(Get-Date))
        if ($forceUpdate) {
            Write-Log "No new changes detected in a long while, refreshing anyway" "INFO"
        }
        if ((-not (([string]$Chezmoi_diff).trim() -in $NoChanges)) -or $forceUpdate) {
            # Next force update time
            (Get-Date).AddHours(6).AddMinutes((Get-Random -Minimum 0 -Maximum 361)).DateTime > "$PSScriptRoot/date.tmp"
            
            # Execute chezmoi update
            & $ChezmoiPath update --init --apply --force 2>&1 | Out-String | Write-Log
            $exitCode = $LASTEXITCODE
            
            if ($exitCode -eq 0) {
                Write-Log "Chezmoi sync completed successfully" "SUCCESS"
            }
            else {
                Write-Log "ERROR: Chezmoi sync failed with exit code $exitCode" "ERROR"
    
                $message = @"
chezmoi update --init --apply --force failed.
Please check your Chezmoi configuration or the sync log for details.

Chezmoi path: $ChezmoiPath
"@
    
                Write-Log "Skipping this sync cycle, will retry on next interval" "WARN"
                throw "chezmoi update --init --apply --force failed with exit code $exitCode"
            }
        }
        else {
            Write-Log "No changes detected from chezmoi git pull" "INFO"
        }
    }
    catch {
        Write-Log "ERROR: Exception during chezmoi sync - $_" "ERROR"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        Write-Log "Skipping this sync cycle, will retry on next interval" "WARN"
        Show-ToastNotification -Message "ERROR: Exception during chezmoi sync - $_" -LogFilePath $ServiceLogFile
        throw
    }
}

function Remove-ServyServiceAndWait {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-zA-Z_-]+$')]
        [string]$ServiceName,
        [string]$ServyModulePath = $script:ServyModulePath
    )

    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $existingService) {
        throw "Service '$ServiceName' not found"
    }

    Write-Log "Service '$ServiceName' found. Stopping and removing..."

    # Try to use Servy if available
    try {
        if (-not (Test-ServyAvailable -ServyModulePath $ServyModulePath)) {
            throw "Servy not available"
        }
    
        Write-Log "Using Servy to remove service..."
        
        # Stop the service
        $null = Stop-ServyService -Quiet -Name $ServiceName -ErrorAction Stop

        # Wait for the service to stop
        $stopped = Wait-ForPredicate -Predicate { 
            $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            (-not $service) -or ($service.Status -eq 'Stopped')
        } -TimeoutSeconds 5 -IntervalSeconds 0.2

        if ($stopped) {
            Write-Log "Service stopped"
        }
        else {
            Write-Log "Service stop timed out" "WARN"
        }

        # Remove the service
        $null = Uninstall-ServyService -Quiet -Name $ServiceName -ErrorAction Stop

        # Wait for service removal confirmation
        $null = Wait-ForPredicate -Predicate { -not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) } -TimeoutSeconds 5 -IntervalSeconds 0.2

        if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
            Write-Log "Warning: Service '$ServiceName' still exists after Servy removal." "WARN"
        }
        else {
            Write-Log "Service removed successfully using Servy"
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
        [ValidatePattern('^[a-zA-Z_-]+$')]
        [string]$ServiceName,
        [string]$ServyModulePath = $script:ServyModulePath
    )
    
    try {
        Write-Log "Starting service... $ServiceName"

        # Try Servy first, fallback to standard Start-Service
        if (Test-ServyAvailable -ServyModulePath $ServyModulePath) {
            Start-ServyService -Quiet -Name $ServiceName -ErrorAction Stop
        }
        else {
            Start-Service -Name $ServiceName -ErrorAction Stop
        }

        # Wait for the service to transition to 'Running' (timeout: 8 seconds)
        $null = Wait-ForPredicate -Predicate { 
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
        [ValidatePattern('^[a-zA-Z_-]+$')]
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

    $Params = "-NoProfile -ExecutionPolicy Bypass -File $ServiceScriptDestFile -Run:$true -Loop:$true"

    # Create the service using Servy
    try {
        if (-not (Test-ServyAvailable -ServyModulePath $ServyModulePath)) {
            throw "Servy not available"
        }
        Write-Log "Creating service using Servy..."

        # Use consistent credential format (full DOMAIN\User format for service)
        $username = $Credentials.UserName  # Full format: DOMAIN\User or MACHINE\User
        $password = $Credentials.GetNetworkCredential().Password
        
        Write-Log "Service will run as: $username"
    


        # Install the service using Servy PowerShell Module
        Install-ServyService `
            -Name $ServiceName `
            -DisplayName $ServiceDisplayName `
            -Description $ServiceDescription `
            -Path $PwshPath `
            -StartupDir $env:USERPROFILE `
            -Params $Params `
            -StartupType "Automatic" `
            -Priority "Normal" `
            -Stdout "$StdoutLogFile" `
            -Stderr "$StderrLogFile" `
            -User $username `
            -Password $password `
            -Quiet

        # Wait for the service to appear in the service list (installed)
        $null = Wait-ForPredicate -Predicate { Get-Service -Name $ServiceName -ErrorAction SilentlyContinue } -TimeoutSeconds 5 -IntervalSeconds 0.2

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
        throw
    }
}


function Set-AdminOnlyPermissions {
    <#
    .SYNOPSIS
    Removes all write permissions except for Administrators and SYSTEM
    
    .DESCRIPTION
    Disables inheritance, removes all existing permissions, and grants:
    - Administrators: Full Control
    - SYSTEM: Full Control
    - Users: Read-only (optional)
    
    .PARAMETER Path
    Path to the file to protect
    
    .PARAMETER AllowUsersRead
    If specified, allows Users group to read the file. Otherwise, only Admins and SYSTEM have access.
    
    .EXAMPLE
    Set-AdminOnlyPermissions -Path "C:\path\to\file.txt"
    
    .EXAMPLE
    Set-AdminOnlyPermissions -Path "C:\path\to\file.txt" -AllowUsersRead
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [switch]$AllowUsersRead
    )
    
    process {
        if (-not (Test-Path $Path)) {
            Write-Error "File not found: $Path"
            return
        }
        
        try {
            # Get current ACL
            $acl = Get-Acl $Path
            
            # Disable inheritance (protect from parent permissions)
            # First parameter: true = disable inheritance
            # Second parameter: false = remove inherited rules
            $acl.SetAccessRuleProtection($true, $false)
            
            # Remove all existing access rules
            $acl.Access | ForEach-Object { 
                $acl.RemoveAccessRule($_) | Out-Null
            }
            
            # Add Administrator full control
            $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "Administrators",
                "FullControl",
                "Allow"
            )
            $acl.AddAccessRule($adminRule)
            
            # Add SYSTEM full control (recommended for system stability)
            $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "SYSTEM",
                "FullControl",
                "Allow"
            )
            $acl.AddAccessRule($systemRule)
            
            # Optionally: Add read-only for Users
            if ($AllowUsersRead) {
                $readRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    "Users",
                    "Read",
                    "Allow"
                )
                $acl.AddAccessRule($readRule)
            }
            
            # Apply the changes
            Set-Acl $Path $acl
            
            $message = if ($AllowUsersRead) {
                "Users have read-only access"
            }
            else {
                "Only Administrators and SYSTEM have access"
            }
            Write-Log "File now has admin-only permissions, $($message): $Path" "INFO"
        }
        catch {
            Write-Log "Failed to set permissions: $_" "ERROR"
        }
    }
}
function Reset-FilePermissions {
    <#
    .SYNOPSIS
    Resets file permissions to inherit from parent folder (default state)
    
    .PARAMETER Path
    Path to the file to reset permissions
    
    .EXAMPLE
    Reset-FilePermissions -Path "C:\path\to\file.txt"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Path
    )
    
    process {
        if (-not (Test-Path $Path)) {
            Write-Error "File not found: $Path"
            return
        }
        
        try {
            # Get current ACL
            $acl = Get-Acl $Path
            
            # Enable inheritance from parent folder
            # SetAccessRuleProtection(false, false)
            # - First parameter: false = enable inheritance
            # - Second parameter: false = remove explicit permissions
            $acl.SetAccessRuleProtection($false, $false)
            
            # Apply the changes
            Set-Acl $Path $acl
            
            Write-Log "File now inherits permissions from parent folder: $Path" "INFO"
        }
        catch {
            Write-Log "Failed to reset permissions: $_" "ERROR"
        }
    }
}
# ============================================================================
# PARAMETER VALIDATION AND INITIALIZATION
# ============================================================================

# Log file paths (parameter dependent)
if ($PSCmdlet.ParameterSetName -eq "Install") {
    Assert-CreateDirectory -Path $ServiceDir

    $ServiceLogDir = Join-Path $ServiceDir "logs"
    $ServiceScriptDestFile = Join-Path $ServiceDir $(Split-Path $PSCommandPath -Leaf)
    
    # Ensure ServiceLogDir exists
    try {
        Assert-CreateDirectory -Path $ServiceLogDir
    }
    catch {
        Write-Error $_
        exit 1
    }
    
    $ServiceLogFile = Join-Path $ServiceLogDir $LogFileName
    $StdoutLogFile = $ServiceLogFile
    $StderrLogFile = $ServiceLogFile
}
elseif ($PSCmdlet.ParameterSetName -eq "Uninstall") {
    $ServiceScriptDestFile = $PSCommandPath
    $ServiceDir = $PSScriptRoot
    $ConfigPath = Join-Path $ServiceDir $ConfigFileName
    $ServiceLogDir = Join-Path $ServiceDir "logs"
    $ServiceLogFile = Join-Path $ServiceLogDir $LogFileName
}
elseif ($PSCmdlet.ParameterSetName -eq "Run" -or $PSCmdlet.ParameterSetName -eq "RunLoop") {
    $ServiceScriptDestFile = $PSCommandPath
    $ServiceDir = $PSScriptRoot
    $ServiceLogDir = Join-Path $ServiceDir "logs"
    $ServiceLogFile = Join-Path $ServiceLogDir $LogFileName
}

# ============================================================================
# MAIN EXECUTION LOGIC - Credentials and Administrator privileges
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

# Get current user Credentials for the service if none provided (Install mode only)
if ($PSCmdlet.ParameterSetName -eq "Install") {
    # Validate chezmoi exists and get absolute path
    try {
        $ChezmoiPath = (Get-Command chezmoi -ErrorAction Stop).Source
        Write-Log "Found chezmoi at: $ChezmoiPath"
    }
    catch {
        Write-Log "chezmoi.exe not found in PATH. Please install chezmoi first." "ERROR"
        Write-Log "Visit https://www.chezmoi.io/install/ for installation instructions." "ERROR"
        exit 1
    }
    
    if (-not $Credentials) {
        Write-Host "Please enter your Windows password to configure the service account:" -ForegroundColor Cyan
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
}

# ============================================================================
# MAIN EXECUTION - branch based on parameter set
# ============================================================================
Write-Log "#########################################################" "ALWAYS"
Write-Log "############### Chezmoi Sync Service #####################" "ALWAYS"
Write-Log "#########################################################" "ALWAYS"
Write-Log "Version: $VERSION" "ALWAYS"
if ($PSCmdlet.ParameterSetName -eq "Run" -or $PSCmdlet.ParameterSetName -eq "RunLoop") {
    # ========================================================================
    # RUN MODE - Execute the service loop
    # ========================================================================
    $ConfigPath = Join-Path $ServiceDir $ConfigFileName
    $config = Get-ServiceConfig -ConfigPath $ConfigPath
    # Service configuration - use config if available, otherwise defaults
    if (-not $config) {
        Write-Log "Configuration not found at: $ConfigPath" "ERROR"
        throw "Configuration not found at: $ConfigPath"
    }
    $ChezmoiPath = $config.ChezmoiPath
    $IntervalSeconds = $config.SyncIntervalMinutes * 60
    $LogLevel = $config.LogLevel
    $EnableReAdd = $config.EnableReAdd

    if (-not $(Test-Path $ChezmoiPath) -and -not $(Get-Command $ChezmoiPath)) {
        Write-Log "Chezmoi path not found at: $ChezmoiPath" "ERROR"
        throw "Chezmoi path not found at: $ChezmoiPath"
    }

    $script:LogLevel = $LogLevel ?? "INFO"
    # Graceful shutdown flag
    $script:shouldStop = $false
    
    # Register shutdown handler
    $null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
        $script:shouldStop = $true
        Write-Log "Shutdown signal received" "INFO"
    }
    
    # Main service loop
    Write-Log "Chezmoi path: $ChezmoiPath" "INFO"
    Write-Log "Sync interval: $IntervalSeconds seconds" "INFO"
    
    if ($Loop) {
        try {
            Write-Log "Service started" "INFO"
            while (-not $script:shouldStop) {
                & $PwshPath -NoProfile -ExecutionPolicy Bypass -File $ServiceScriptDestFile -Run:$true -Loop:$false
                # Wait with cancellation check
                $nextSyncTime = (Get-Date).AddSeconds($IntervalSeconds)
                Write-Log "Waiting $IntervalSeconds seconds until next sync..." "INFO"
                Write-Log "Next sync scheduled at: $($nextSyncTime)" "INFO"
                $waited = 0
                while ((-not $script:shouldStop) -and ($waited -lt $IntervalSeconds)) {
                    Start-Sleep -Seconds 1
                    $waited++
                }
            }
            Write-Log "Continuous run finished" "INFO"
        }
        catch {
            Write-Log "FATAL: Service loop terminated - $_" "ERROR"
            Write-Log "Stack trace: $($_.ScriptStackTrace | Out-String)" "ERROR"
            throw
        }
    }
    else {
        try {
            Invoke-ChezmoiSync -ChezmoiPath $ChezmoiPath
            Write-Log "Run finished" "INFO"
        }
        catch {
            Write-Log "Stack trace: $($_.ScriptStackTrace | Out-String)" "ERROR"
            throw
        }
    }
}
elseif ($PSCmdlet.ParameterSetName -eq "Uninstall") {
    # Uninstall mode - remove service and cleanup files
    try {
        # Remove the service
        try {
            Remove-ServyServiceAndWait -ServiceName $ServiceName

        }
        catch {
            if ($_.Exception.Message -like 'Service * not found') {
                Write-Log "Service not found, skipping removal" "WARN"
            }
            else {
                throw
            }
        }
        try {
            if (Test-Path $ConfigPath -ErrorAction SilentlyContinue) {
                Reset-FilePermissions -Path $ConfigPath
            }
        }
        catch {
            Write-Log "Failed to reset permissions for config file: $_" "ERROR"
        }
        try {
            if (Test-Path $ServiceScriptDestFile -ErrorAction SilentlyContinue) {
                Reset-FilePermissions -Path $ServiceScriptDestFile
            }
        }
        catch {
            Write-Log "Failed to reset permissions for service script: $_" "ERROR"
        }
        # Summary
        Write-Log "Uninstallation completed!" "SUCCESS"
        Write-Log "Service '$ServiceName' has been removed from the system"
        Write-Log "You can manually delete related files if no longer needed" # consider using the registry/metadata to track installation path/files?
    }
    catch {
        Write-Log "Uninstallation failed: $_" "ERROR"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        exit 1
    }
}
elseif ($PSCmdlet.ParameterSetName -eq "Install") {
    Write-Log "Starting Chezmoi Sync Service installation..."
    # Install mode - remove any existing service, then install new one
    $serviceCreated = $false
    
    try {
        # Remove any existing service first
        if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
            Write-Log "Removing existing service '$ServiceName'..." "INFO"
            try {
                Remove-ServyServiceAndWait -ServiceName $ServiceName
            }
            catch {
                if ($_.Exception.Message -like 'Service * not found') {
                    Write-Log "Service not found, skipping removal" "WARN"
                }
                else {
                    throw
                }
            }
        }
        
        # Create configuration file
        $ConfigPath = Join-Path $ServiceDir $ConfigFileName
        
        Save-ServiceConfig `
            -ConfigPath $ConfigPath `
            -ChezmoiPath $ChezmoiPath `
            -SyncIntervalMinutes $SyncIntervalMinutes
        Set-AdminOnlyPermissions -Path $ConfigPath -AllowUsersRead
        
        # Copy this script with consistent name
        $currentScriptPath = $PSCommandPath
        try {
            Copy-Item -Path $currentScriptPath -Destination $ServiceDir -Force -ErrorAction Stop
        }
        catch {
            # If copying failed because the source and destination are the same, continue silently
            if ($_.Exception.Message -like 'Cannot overwrite the item * with itself.') {
            }
            else {
                throw
            }
        }
        Write-Log "Service script copied and verified: $ServiceDir" "SUCCESS"
        Set-AdminOnlyPermissions -Path $ServiceScriptDestFile -AllowUsersRead

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
        Write-Log "Service installation completed!" "SUCCESS"
        Write-Log "Service Name: $ServiceName"
        Write-Log "Display Name: $ServiceDisplayName"
        Write-Log "Service Directory: $ServiceDir"
        Write-Log "Service Log File: $ServiceLogFile"
        Write-Log "Config File: $ConfigPath"
        Write-Log "To check service status: Get-Service -Name '$ServiceName'"
        Write-Log "To view service logs: Get-Content '$ServiceLogFile' -Tail 20"
    }
    catch {
        Write-Log "Installation failed: $_" "ERROR"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        # Remove service if it was created on failure
        try {
            if (Test-Path $ConfigPath -ErrorAction SilentlyContinue) {
                Reset-FilePermissions -Path $ConfigPath
            }
        }
        catch {
            Write-Log "Failed to reset permissions for config file: $_" "ERROR"
        }
        try {
            if (Test-Path $ServiceScriptDestFile -ErrorAction SilentlyContinue) {
                Reset-FilePermissions -Path $ServiceScriptDestFile
            }
        }
        catch {
            Write-Log "Failed to reset permissions for service script: $_" "ERROR"
        }
        if ($serviceCreated) {
            try {
                Write-Log "Rolling back service installation, removing service..." "WARN"
                Remove-ServyServiceAndWait -ServiceName $ServiceName
                Write-Log "Service rollback completed" "INFO"
            }
            catch {
                Write-Log "Failed to rollback service: $_" "WARN"
            }
        }
        exit 1
    }
}
else {
    Write-Log "INTERNAL ERROR: Unknown parameter set '$($PSCmdlet.ParameterSetName)'. This should never happen." "ERROR"
    exit 1
}