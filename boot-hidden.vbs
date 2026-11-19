' dsh-mobile ????????????boot.ps1 ????
' ??? watchdog-hidden.vbs?????????? powershell ???????
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
here = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = here & "\boot.ps1"
If Not fso.FileExists(ps1) Then WScript.Quit 1
cmd = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & ps1 & """ -Port 8765"
sh.Run cmd, 0, False
WScript.Quit 0