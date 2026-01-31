# Chezmoi Sync Service Wrapper
# This script runs continuously as a Windows Service, executing chezmoi init --apply every 5 minutes

# Configuration
$ChezmoiPath = (Get-Command chezmoi).Source #"$env:USERPROFILE\.local\bin\chezmoi.exe"
$LogDir = "$env:USERPROFILE\.local\share\chezmoi-sync\logs"
$LogFile = Join-Path $LogDir "sync-service.log"
$IntervalSeconds = 5 * 60  # 5 minutes

# Ensure log directory exists
if (-not (Test-Path $LogDir)) {
    try {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    catch {
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
                Write-Log "Unable to open log file automatically: $_"
            }
        }
        ([System.Windows.Forms.DialogResult]::No) {
            # Copy Path button clicked
            try {
                $LogFilePath | Set-Clipboard
                Write-Log "Log file path copied to clipboard"
                [System.Windows.Forms.MessageBox]::Show(
                    "Log file path copied to clipboard:`n$LogFilePath",
                    "Copied!",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            }
            catch {
                Write-Log "Failed to copy log file path to clipboard: $_"
            }
        }
    }
    # OK or X button: do nothing
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
        
        # Execute chezmoi re-add before init --apply
        Write-Log "Running chezmoi re-add..."
        $reAddOutput = & $ChezmoiPath re-add 2>&1 | Tee-Object -FilePath $LogFile -Append
        $reAddExitCode = $LASTEXITCODE

        if ($reAddExitCode -eq 0) {
            Write-Log "chezmoi re-add completed successfully"
        }
        else {
            Write-Log "ERROR: chezmoi re-add failed with exit code $reAddExitCode"

            $message = @"
chezmoi re-add failed.
Please check your Chezmoi configuration or the sync log for details.

Chezmoi path: $ChezmoiPath
Log file: $LogFile
"@

            Show-ErrorDialog -Message $message -LogFilePath $LogFile
            exit 1
        }

        # Execute chezmoi init --apply
        $output = & $ChezmoiPath update --init --apply --force 2>&1 | Tee-Object -FilePath $LogFile -Append
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            Write-Log "Chezmoi sync completed successfully"
            if ($output) {
                # Write-Log "Output: $output"
            }
        }
        else {
            Write-Log "ERROR: Chezmoi sync failed with exit code $exitCode"

            $message = @"
chezmoi init --apply failed.
Please check your Chezmoi configuration or the sync log for details.

Chezmoi path: $ChezmoiPath
Log file: $LogFile
"@

            Show-ErrorDialog -Message $message -LogFilePath $LogFile
        }
        exit 1

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
