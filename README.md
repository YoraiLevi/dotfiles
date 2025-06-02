## [Project Requirements Documents](https://docs.google.com/document/d/1YMBDaniOEwUiMpM2-22DQS6xsGwZ5SLFlhoZ_u54h9Q/edit?tab=t.0) - Google Docs reference

More TODOS:
Refresh start menu after start.bin update - How can I restart start menu? https://superuser.com/a/1617476/1220772  
bash unlimited history https://stackoverflow.com/a/19533853/12603110  
https://app.sparkmailapp.com/web-share/ZYcTULhKr4caHTKFzmK3TeTTV2eMz0ILf9CBNZPl  
powercfg and power configurations  
explorer and taskbar pins  
powershell modules  
wsl stuff  
rust? compiled languages toolchains...  
registry -> learn how to merge without admin permission  
disable rotation https://superuser.com/a/1833703/1220772  
powershell on exit execute code https://stackoverflow.com/a/31119208/12603110  

Development references
1) ~~Validate templates compile~~ Reduce template use
2) Validate code could work in theory - linter etc
3) setup powershell pester5 tests
4) automated tests with vm?
5) better vagrant setup?

TODO read about [Special files and directories](https://www.chezmoi.io/reference/special-files-and-directories/)  
test again and report bug related to vscode typing issue when editor is specified on toml  
1) don't use editor variable in env  
2) dont use conda/posh  
3) pwsh.exe vs cmd.exe vs default  
4) getting system info:
   1) https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-computersystem
   2) https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-systemenclosure
   3) https://techuisitive.com/enclosure-chassis-types-value-description-configmgr-sccm/?expand_article=1
5) windows update pausing
   1) https://stackoverflow.com/questions/62424065/pause-windows-update-for-up-to-35-days-and-find-out-until-which-date-updates-are

reference examples:  
https://github.com/mimikun/dotfiles/tree/master  
https://github.com/SeeminglyScience/dotfiles/tree/main  

Avoiding admin: What registry objects could be (over)written using `HKEY_CURRENT_USER` https://stackoverflow.com/a/19149700/12603110
How to install chocolatey software without admin?


------------------
# Yorai's Dotfiles
## [How to use reference & Profile Command Features](DOCS_FEATURES.md)
## [Chezmoi Dotfile repository](https://www.chezmoi.io/user-guide/daily-operations/)

### Daily use
Opening terminal, fetching updates?
```
```

Editing profile
```
eds # only edit template files
chezmoi re-add # updates everything but templates
```
Editing general tracked dotfiles? - TODO
```
```

#### To setup a system:
```
$ENV:SYSTEM_NAME = ""
$GITHUB_USERNAME = "YoraiLevi"
irm https://raw.githubusercontent.com/YoraiLevi/dotfiles/master/Install.ps1 | iex
```

```
$ENV:SYSTEM_NAME = "TP412FAC"
$ENV:SYSTEM_NAME = "VirtualMachine"
```

Re-setup an existing system - Resolve conflicts/erros
* with new machine name settings?
* with existing machine name?

Remove from system?
```
```

### Development of setup
[Debugging all `run_` scripts](https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/#clear-the-state-of-all-run_onchange_-and-run_once_-scripts)
```
chezmoi state delete-bucket --bucket=entryState; chezmoi state delete-bucket --bucket=scriptState; chezmoi init; chezmoi apply
```

Debugging templates
```
cat template.tmpl | chezmoi execute-template $_
```

Character order:
```
PS> [string](33..126 | %{$([string][char]$_)} | sort)

_ - , ; : ! ? . ' " ( ) [ ] { } @ * / \ & # % ` ^ + < = > | ~ $ 0 1 2 3 4 5 6 7 8 9 A a B b C c d D e E f F g G h H I i j J K k L l m M n N o O P p Q q R r s S T t U u v V w W x X y Y Z z
```
