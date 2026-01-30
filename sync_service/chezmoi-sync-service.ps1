# Chezmoi Sync Service Wrapper
# This script runs continuously as a Windows Service, executing chezmoi init --apply every 5 minutes

# Configuration
$ChezmoiPath = (get-command chezmoi).Source #"$env:USERPROFILE\.local\bin\chezmoi.exe"
$LogDir = "$env:USERPROFILE\.local\share\chezmoi-sync\logs"
$LogFile = Join-Path $LogDir "sync-service.log"
$IntervalSeconds = 5*60  # 5 minutes

# Ensure log directory exists
if (-not (Test-Path $LogDir)) {
    try {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    } catch {
        throw
    }
}

# Function to write log entries
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Add-Content -Path $LogFile -Value $logMessage
    Write-Host $logMessage
}

# Function to execute chezmoi command
function Invoke-ChezmoiSync {
    try {
        Write-Log "Starting chezmoi sync..."
        
        # Check if chezmoi.exe exists
        if (-not (Test-Path $ChezmoiPath)) {
            Write-Log "ERROR: chezmoi.exe not found at $ChezmoiPath"
            return
        }
        
        # Execute chezmoi init --apply
        $output = & $ChezmoiPath init --apply --force 2>&1
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            Write-Log "Chezmoi sync completed successfully"
            if ($output) {
                Write-Log "Output: $output"
            }
        } else {
            Write-Log "ERROR: Chezmoi sync failed with exit code $exitCode"
            Write-Log "Output: $output"
        }
    }
    catch {
        Write-Log "ERROR: Exception during chezmoi sync - $_"
        Write-Log "Stack trace: $($_.ScriptStackTrace)"
    }
}

# Main service loop
Write-Log "Chezmoi Sync Service started"
Write-Log "Chezmoi path: $ChezmoiPath"
Write-Log "Sync interval: $IntervalSeconds seconds"

try {
    while ($true) {
        Invoke-ChezmoiSync
        
        Write-Log "Waiting $IntervalSeconds seconds until next sync..."
        Start-Sleep -Seconds $IntervalSeconds
    }
}
catch {
    Write-Log "FATAL: Service loop terminated - $_"
    throw
}
finally {
    Write-Log "Chezmoi Sync Service stopped"
}
