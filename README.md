## [Project Requirements Documents](https://docs.google.com/document/d/1YMBDaniOEwUiMpM2-22DQS6xsGwZ5SLFlhoZ_u54h9Q/edit?tab=t.0) - Google Docs reference

Development references

1. ~~Validate templates compile~~ Reduce template use `Get-ChildItem -Path . -Filter *.ps1.tmpl -Recurse | % {$_.FullName}`
2. Validate code could work in theory - linter etc for pwsh? bash?
3. setup powershell pester5 tests
4. automated tests with vm?
5. better vagrant setup?

TODO read about chezmoi [Special files and directories](https://www.chezmoi.io/reference/special-files-and-directories/)  
test again and report bug related to vscode typing issue when editor is specified on toml

reference examples:  
<https://github.com/mimikun/dotfiles/tree/master>  
<https://github.com/SeeminglyScience/dotfiles/tree/main>

---

# Yorai's Dotfiles

## [How to use reference & Profile Command Features](DOCS_FEATURES.md)

## [Chezmoi Dotfile repository](https://www.chezmoi.io/user-guide/daily-operations/)

### Daily use

Opening terminal, fetching updates?

```text

```

Applying updates from local

```sh
chezmoi init --apply
```

Editing profile

```sh

```

```sh
eds # only edit template files
chezmoi re-add # updates everything but templates
```

Editing general tracked dotfiles? - TODO

```text

```

Listing variables

```sh
chezmoi data
```

#### To setup a system

```sh
$ENV:SYSTEM_NAME = ""
$GITHUB_USERNAME = "YoraiLevi"
irm https://raw.githubusercontent.com/YoraiLevi/dotfiles/master/Install.ps1 | iex
```

```sh
$ENV:SYSTEM_NAME = "TP412FAC"
$ENV:SYSTEM_NAME = "VirtualMachine"
```

Re-setup an existing system - Resolve conflicts/erros

* with new machine name settings?
* with existing machine name?

Remove from system?

```text

```

### Development of setup

[Debugging all `run_` scripts](https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/#clear-the-state-of-all-run_onchange_-and-run_once_-scripts)

```sh
chezmoi state delete-bucket --bucket=entryState; chezmoi state delete-bucket --bucket=scriptState; chezmoi init; chezmoi apply
```

Debugging templates

```sh
cat template.tmpl | chezmoi execute-template $_
```

#### Debugging

Profiling pwsh profile performance

This doesn't work well:

```pwsh
pwsh.exe -NoProfile -command 'Measure-Script -Top 10 $profile.CurrentUserAllHosts'
```

Using the custom `.chezmoilib` folder with pwsh and chezmoi

```pwsh
Import-Module (Join-Path $ENV:CHEZMOI_SOURCE_DIR .chezmoilib\DesktopIniAttributes.psm1)

Get-ChildItem -Path $ENV:CHEZMOI_SOURCE_DIR -Filter desktop.ini -Recurse | ForEach-Object {
    Remove-DesktopIniAttributes $_.FullName -ErrorAction Continue
}
```
