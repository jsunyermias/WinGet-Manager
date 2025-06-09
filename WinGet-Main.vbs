Set shell = CreateObject("Shell.Application")
Set wshell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Expand %ProgramData%
programData = wshell.ExpandEnvironmentStrings("%ProgramData%")
scriptPath = programData & "\WinGet-extra\WinGet-Main.ps1"
testPath = programData & "\WinGet-extra\admin-test.tmp"

' Check if the PowerShell script exists
If Not fso.FileExists(scriptPath) Then
    MsgBox "The PowerShell script was not found: " & scriptPath, vbCritical, "Error"
    WScript.Quit
End If

On Error Resume Next
Set testFile = fso.CreateTextFile(testPath, True)
If Err.Number <> 0 Then
    ' Not running as administrator: relaunch with elevated privileges
    shell.ShellExecute "powershell.exe", "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File """ & scriptPath & """", "", "runas", 0
    WScript.Quit
End If
testFile.Close
fso.DeleteFile testPath, True
On Error GoTo 0

' Already running as administrator: run in background
wshell.Run "powershell -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File """ & scriptPath & """", 0, False
