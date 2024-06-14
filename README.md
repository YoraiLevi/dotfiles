# [Chezmoi Dotfile repository](https://www.chezmoi.io/user-guide/daily-operations/)

To setup a system:
```
$GITHUB_USERNAME = "YoraiLevi"
irm https://raw.githubusercontent.com/YoraiLevi/dotfiles/master/Install.ps1 | iex
```

[Debugging all `run_` scripts](https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/#clear-the-state-of-all-run_onchange_-and-run_once_-scripts)
```
chezmoi state delete-bucket --bucket=entryState; chezmoi state delete-bucket --bucket=scriptState; chezmoi init; chezmoi apply
```

Debugging templates
```
cat template.tmpl | chezmoi execute-template $_
```

TODO read about [Special files and directories](https://www.chezmoi.io/reference/special-files-and-directories/)  
test again and report bug related to vscode typing issue when editor is specified on toml  
1) don't use editor variable in env  
2) dont use conda/posh  
3) pwsh.exe vs cmd.exe vs default  

reference examples:  
https://github.com/mimikun/dotfiles/tree/master  
https://github.com/SeeminglyScience/dotfiles/tree/main  

Avoiding admin: What registry objects could be (over)written using `HKEY_CURRENT_USER` https://stackoverflow.com/a/19149700/12603110
How to install chocolatey software without admin?

Character order:
```
PS> [string](33..126 | %{$([string][char]$_)} | sort)

_ - , ; : ! ? . ' " ( ) [ ] { } @ * / \ & # % ` ^ + < = > | ~ $ 0 1 2 3 4 5 6 7 8 9 A a B b C c d D e E f F g G h H I i j J K k L l m M n N o O P p Q q R r s S T t U u v V w W x X y Y Z z
```
