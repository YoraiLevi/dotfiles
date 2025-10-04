param()
$ENV:CHEZMOI_DATA = (chezmoi data --format json | Out-String | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 100)
$ENV:CHEZMOI_WSL2 = 1
$slashFlags = [hashtable]@{
    "CHEZMOI_CACHE_DIR"    = "/up"
    "CHEZMOI_COMMAND_DIR"  = "/up"
    "CHEZMOI_CONFIG_FILE"  = "/up"
    "CHEZMOI_DEST_DIR"     = "/up"
    "CHEZMOI_EXECUTABLE"   = "/up"
    "CHEZMOI_HOME_DIR"     = "/up"
    "CHEZMOI_SOURCE_DIR"   = "/up"
    "CHEZMOI_WORKING_TREE" = "/up"
    "CHEZMOI_ARGS"         = "/up"
}
$envArgs = Get-ChildItem Env: | Where-Object { $_.Name -like 'CHEZMOI*' }
# https://devblogs.microsoft.com/commandline/share-environment-vars-between-wsl-and-windows/
$env:WSLENV = $env:WSLENV + ":" + ( ($envArgs | ForEach-Object { "$($_.Name)$($slashFlags[$_.Name])" }) -join ':')
wsl bash --noprofile --norc "$(wsl wslpath $args.replace('\','/'))"