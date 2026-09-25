[CmdletBinding()]
param(
    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $root '.local\bin\AutoHotkey64.exe'
$script = Join-Path $PSScriptRoot 'display-switch-windows.ahk'
$icon = Join-Path $root 'assets\apple-switch.ico'
$startup = [Environment]::GetFolderPath('Startup')
$link = Join-Path $startup 'Display Switch Control.lnk'
$arguments = '"' + $script + '"'

if (-not $startup -or -not (Test-Path -LiteralPath $startup -PathType Container)) {
    throw 'Current-user Startup folder was not found.'
}

$shell = New-Object -ComObject WScript.Shell
if (Test-Path -LiteralPath $link -PathType Leaf) {
    $existing = $shell.CreateShortcut($link)
    if ($existing.TargetPath -ne $exe -or $existing.Arguments -ne $arguments) {
        throw "Startup shortcut belongs to another target: $link"
    }
    if ($Remove) {
        Remove-Item -LiteralPath $link
        Write-Output "Removed current-user startup shortcut: $link"
        return
    }
} elseif ($Remove) {
    Write-Output "No current-user startup shortcut exists: $link"
    return
}

foreach ($path in @($exe, $script, $icon)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Startup target file missing: $path"
    }
}

$shortcut = $shell.CreateShortcut($link)
$shortcut.TargetPath = $exe
$shortcut.Arguments = $arguments
$shortcut.WorkingDirectory = $root
$shortcut.IconLocation = $icon + ',0'
$shortcut.Description = 'Display Switch Control'
$shortcut.Save()
Write-Output "Installed current-user startup shortcut: $link"
