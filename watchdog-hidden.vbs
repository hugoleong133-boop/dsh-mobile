' dsh-mobile 看门狗的静默启动器
'
' 为什么需要这一层：
'   计划任务直接调用 powershell.exe 时，Windows 会先给 conhost 建一个控制台窗口，
'   之后 powershell 才处理 -WindowStyle Hidden。那一瞬的窗口就是用户看到的闪屏。
'   wscript 是无窗口宿主，用 WScript.Shell.Run 以窗口状态 0 启动子进程，
'   子进程的 conhost 从创建起就是隐藏的，不会闪。
'
' 路径全部在运行时从脚本自身位置推导，文件内容保持纯 ASCII，
' 避免中文目录带来的编码问题。

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")

here = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = here & "\watchdog.ps1"

If Not fso.FileExists(ps1) Then
    WScript.Quit 1
End If

cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """ -Port 8765"

' 0 = 隐藏窗口, False = 不等待
sh.Run cmd, 0, False
WScript.Quit 0
