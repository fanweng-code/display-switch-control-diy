[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $root '.local\bin\AutoHotkey64.exe'
$script = Join-Path $PSScriptRoot 'display-switch-windows.ahk'

if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "AutoHotkey v2 portable runtime missing: $exe"
}
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
    throw "Windows hotkey script missing: $script"
}

Start-Process -FilePath $exe -ArgumentList ('"' + $script + '"') -WorkingDirectory $root -WindowStyle Hidden
Write-Output "Started Windows Ctrl+Alt+Shift+M listener; log: $root\.local\logs\windows-hotkey.log"
