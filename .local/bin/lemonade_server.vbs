Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
Set WshShell = CreateObject("WScript.Shell")
cmd = """" & scriptDir & "\lemonade.exe"" server"
WshShell.Run cmd, 0, False
