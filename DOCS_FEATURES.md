### Available Commands

 ```ps1
 Get-Content .\Documents\PowerShell\profile.ps1 | Select-String -Pattern ("(?:^function ([\w-]+?)[\s{\(])|(?:^Set-Alias.+?-Name ([\w-]+?) )") | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Groups | Where-Object {($_.Name -eq 1 -or  $_.Name -eq 2) -and $_.Success -eq $True} | Select-Object -ExpandProperty Value
 ```
code  
vscode  
Update-PowerShell  
Invoke-Profile  
Edit-Profile  
edp  
Edit-ChezmoiConfig  
Edit-Setup  
which  
export  
pkill  
head  
tail  
home  
user  
docs  
documents  
source  
sources  
dtop  
desktop  
ll  
Touch-File  
touch  
Get-Env  
Add-EnvPathLast  
Add-EnvPathFirst  
Remove-EnvPath  
Get-EnvPath  
Find-EnvPath  