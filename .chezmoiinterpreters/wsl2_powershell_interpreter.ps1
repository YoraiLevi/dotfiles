param()
$ENV:CHEZMOI_DATA = (chezmoi data | Out-String | ConvertFrom-Json | ConvertTo-Json -Compress)
$slashFlags = [hashtable]@{
    "CHEZMOI_CACHE_DIR"    = "/up"
    "CHEZMOI_COMMAND_DIR"  = "/up"
    "CHEZMOI_CONFIG_FILE"  = "/up"
    "CHEZMOI_DEST_DIR"     = "/up"
    "CHEZMOI_EXECUTABLE"   = "/up"
    "CHEZMOI_HOME_DIR"     = "/up"
    "CHEZMOI_SOURCE_DIR"   = "/up"
    "CHEZMOI_WORKING_TREE" = "/up"
}
$env:WSLENV = $env:WSLENV + ":" + ((Get-ChildItem Env: | Where-Object { $_.Name -like 'CHEZMOI*' } | ForEach-Object { "$($_.Name)$($slashFlags[$_.Name])" }) -join ':')
wsl bash --noprofile --norc "$(wsl wslpath $args.replace('\','/'))"