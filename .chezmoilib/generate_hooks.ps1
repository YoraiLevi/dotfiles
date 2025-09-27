param(
    [Parameter(Mandatory = $true)]
    [string]$HooksDir,
    
    [Parameter(Mandatory = $true)]
    [string]$PwshPath
)

$hooks = @{}
if (Test-Path $HooksDir) {
    Get-ChildItem -Path $HooksDir -Directory | ForEach-Object {
        $hookName = $_.Name
        $hookPath = $_.FullName
        $hookConfig = @{}
        
        $preScript = Get-ChildItem -Path $hookPath -Filter 'pre*' -File | Select-Object -First 1
        if ($preScript) {
            $hookConfig['pre'] = @{
                'command' = $PwshPath
                'args' = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', "$hookPath/$($preScript.Name)")
            }
        }
        
        $postScript = Get-ChildItem -Path $hookPath -Filter 'post*' -File | Select-Object -First 1
        if ($postScript) {
            $hookConfig['post'] = @{
                'command' = $PwshPath
                'args' = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', "$hookPath/$($postScript.Name)")
            }
        }
        
        if ($hookConfig.Count -gt 0) {
            $hooks[$hookName] = $hookConfig
        }
    }
}
@{hooks = $hooks} | ConvertTo-Json -Depth 4 -Compress
