#Requires AutoHotkey v2.0
#SingleInstance Force

projectRoot := A_ScriptDir "\.."
switchScript := A_ScriptDir "\display-switch-windows.ps1"
logDir := projectRoot "\.local\logs"
DirCreate logDir
logPath := logDir "\windows-hotkey.log"
busy := false
lastTrigger := 0

TraySetIcon projectRoot "\assets\apple-switch.ico"
A_IconTip := "Switch to Mac · Ctrl+Alt+Shift+M"
A_TrayMenu.Delete()
A_TrayMenu.Add("Hotkey: Ctrl + Alt + Shift + M", NoAction)
A_TrayMenu.Disable("Hotkey: Ctrl + Alt + Shift + M")
A_TrayMenu.Add("Switch to Mac", ManualSwitch)
A_TrayMenu.Add("Exit", ExitMenu)
A_TrayMenu.Default := ""

FileAppend A_Now " started pid=" DllCall("GetCurrentProcessId") "`n", logPath, "UTF-8"

NoAction(*) {
}

ManualSwitch(*) {
    SwitchToMac("menu")
}

ExitMenu(*) {
    ExitApp()
}

^!+m::SwitchToMac("hotkey")

SwitchToMac(source) {
    global projectRoot, switchScript, logPath, busy, lastTrigger

    ; Ignore keyboard auto-repeat and overlapping switch attempts.
    if busy || (A_TickCount - lastTrigger < 5000)
        return
    busy := true
    lastTrigger := A_TickCount

    try {
        FileAppend A_Now " " source " switch requested`n", logPath, "UTF-8"
        command := 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' switchScript '" mac'
        exitCode := RunWait(command, projectRoot, "Hide")
        FileAppend A_Now " switch exit=" exitCode "`n", logPath, "UTF-8"
    } catch Error as err {
        FileAppend A_Now " switch error=" err.Message "`n", logPath, "UTF-8"
    } finally {
        busy := false
    }
}
