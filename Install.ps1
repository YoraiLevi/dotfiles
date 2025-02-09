if ($GITHUB_USERNAME -eq $null){
    throw "Github username variable isn't set!"
}
function Test-Administrator {  
    $user = [Security.Principal.WindowsIdentity]::GetCurrent();
    (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)  
}
function Throw-NotAdministrator {
    if ((Test-Administrator) -eq $false) {
        throw "Access denied. Please run as an administrator."
    }
}
Throw-NotAdministrator -ErrorAction Stop
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
choco install pwsh -y # this must be bootstrapped outside of chezmoi for some reason!
iex "&{$(irm 'https://get.chezmoi.io/ps1')} -BinDir '$HOME/.local/bin/' init --apply '$GITHUB_USERNAME'" | Tee-Object -FilePath $Home/CHEZMOI.log -Append
