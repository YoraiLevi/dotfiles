param()
# Intentionally empty. The forget/add logic lives in pre.ps1 because chezmoi
# holds its BoltDB persistent-state lock between pre and post hooks; any
# nested `chezmoi forget`/`chezmoi add` call from here races the parent and
# fails with "timeout obtaining persistent state lock".
#
# If you are considering adding work here: put it in pre.ps1 instead, or
# perform it as plain filesystem/git operations that do not shell out to
# chezmoi.
Write-Host $PSCommandPath -ForegroundColor Green
