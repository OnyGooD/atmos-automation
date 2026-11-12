Set WshShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")

scriptDir = FSO.GetParentFolderName(WScript.ScriptFullName)

powershellPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
watcherPath = scriptDir & "\AtmosWatcher.ps1"

command = """" & powershellPath & """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & watcherPath & """"

WshShell.Run command, 0, False