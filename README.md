# [Chezmoi Dotfile repository](https://www.chezmoi.io/user-guide/daily-operations/)

To setup a system:
```
$GITHUB_USERNAME = "YoraiLevi"
iex "&{$(irm 'https://get.chezmoi.io/ps1')} init --apply '$GITHUB_USERNAME'"
```

TODO read about [Special files and directories](https://www.chezmoi.io/reference/special-files-and-directories/)  
test again and report bug related to vscode typing issue when editor is specified on toml  
1) don't use editor variable in env  
2) dont use conda/posh  
3) pwsh.exe vs cmd.exe vs default  

reference examples:  
https://github.com/mimikun/dotfiles/tree/master  
https://github.com/SeeminglyScience/dotfiles/tree/main  