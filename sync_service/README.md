# Chezmoi Sync Service

A Windows Service that automatically runs `chezmoi init --apply` every 5 minutes to keep your dotfiles synchronized.

## Files

- **`install_sync_service.ps1`** - Installation script (creates and starts the service)
- **`chezmoi-sync-service.ps1`** - Service wrapper script (runs continuously)
- **`uninstall_sync_service.ps1`** - Uninstallation script (removes the service)

## Installation

1. **Open PowerShell as Administrator**
   - Right-click PowerShell and select "Run as Administrator"

2. **Run the installation script:**
   ```powershell
   cd C:\Users\devic\.local\share\chezmoi\sync_service
   .\install_sync_service.ps1
   ```

3. **Enter your Windows password when prompted**
   - The service needs to run under your user account to access your dotfiles
   - Your password is only used to configure the service and is not stored

4. **Verify the service is running:**
   ```powershell
   Get-Service -Name ChezmoiSync
   ```

## Configuration

- **Service Name:** `ChezmoiSync`
- **Display Name:** `Chezmoi Sync Service`
- **Command:** `chezmoi init --apply`
- **Interval:** Every 5 minutes (300 seconds)
- **Chezmoi Path:** `%USERPROFILE%\.local\bin\chezmoi.exe`

## Logs

The service creates detailed logs for monitoring and troubleshooting:

- **Service Logs:** `%USERPROFILE%\.local\share\chezmoi-sync\logs\sync-service.log`
- **Installation Log:** `%USERPROFILE%\.local\share\chezmoi-sync\logs\install.log`
- **Uninstallation Log:** `%USERPROFILE%\.local\share\chezmoi-sync\logs\uninstall.log`

### View Recent Logs

```powershell
# View last 20 lines of service log
Get-Content "$env:USERPROFILE\.local\share\chezmoi-sync\logs\sync-service.log" -Tail 20

# Monitor logs in real-time
Get-Content "$env:USERPROFILE\.local\share\chezmoi-sync\logs\sync-service.log" -Wait -Tail 10
```

## Management

### Check Service Status
```powershell
Get-Service -Name ChezmoiSync
```

### Start the Service
```powershell
Start-Service -Name ChezmoiSync
```

### Stop the Service
```powershell
Stop-Service -Name ChezmoiSync
```

### Restart the Service
```powershell
Restart-Service -Name ChezmoiSync
```

### View Service Details
```powershell
Get-Service -Name ChezmoiSync | Select-Object *
```

## Uninstallation

To remove the service:

1. **Open PowerShell as Administrator**

2. **Run the uninstallation script:**
   ```powershell
   cd C:\Users\devic\.local\share\chezmoi\sync_service
   .\uninstall_sync_service.ps1
   ```

This will:
- Stop the service if running
- Remove the service from Windows
- Delete the wrapper script
- Preserve log files for your review

## Troubleshooting

### Service Fails to Start

1. **Check if chezmoi.exe exists:**
   ```powershell
   Test-Path "$env:USERPROFILE\.local\bin\chezmoi.exe"
   ```

2. **Verify wrapper script location:**
   ```powershell
   Test-Path "$env:USERPROFILE\.local\bin\chezmoi-sync-service.ps1"
   ```

3. **Check service logs for errors:**
   ```powershell
   Get-Content "$env:USERPROFILE\.local\share\chezmoi-sync\logs\sync-service.log" -Tail 50
   ```

### Permission Issues

The service must run as your user account to access:
- Your chezmoi source directory: `%USERPROFILE%\.local\share\chezmoi`
- Your dotfiles destination: `%USERPROFILE%`
- Git repositories and credentials

If you change your Windows password, you'll need to:
1. Uninstall the service
2. Reinstall it with the new password

### Manual Service Configuration

If needed, you can modify the service using `sc.exe`:

```powershell
# Change startup type to manual
sc.exe config ChezmoiSync start= demand

# Change back to automatic
sc.exe config ChezmoiSync start= auto
```

## Technical Details

### How It Works

1. **Installation Script** copies the wrapper script to a permanent location and creates a Windows Service using NSSM
2. **Windows Service** launches PowerShell with the wrapper script
3. **Wrapper Script** runs in an infinite loop:
   - Executes `chezmoi init --apply`
   - Logs the results
   - Sleeps for 5 minutes
   - Repeats

### Service Account

The service runs under your Windows user account because:
- Chezmoi needs access to your home directory (`%USERPROFILE%`)
- Git credentials are stored per-user
- The chezmoi source directory is in your user profile

### Modifying the Sync Interval

To change the sync frequency, edit the wrapper script:

```powershell
# Edit the wrapper script
notepad "$env:USERPROFILE\.local\bin\chezmoi-sync-service.ps1"

# Find and modify this line:
$IntervalSeconds = 300  # Change this number (in seconds)

# Restart the service to apply changes
Restart-Service -Name ChezmoiSync
```

Common intervals:
- 5 minutes: `300`
- 10 minutes: `600`
- 15 minutes: `900`
- 30 minutes: `1800`
- 1 hour: `3600`

## Notes

- The service runs continuously in the background
- Each sync execution is logged with timestamps
- The service will survive system reboots (automatic startup)
- Multiple sync operations won't overlap (sequential execution)
