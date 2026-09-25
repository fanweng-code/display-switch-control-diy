[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'mac')]
    [string]$Command = 'status',

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $root '.local\bin\monitor-switch.exe'
$configPath = Join-Path $root '.local\config\windows.psd1'
if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) {
    throw "Windows Monitor Switch CLI missing: $cli"
}
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Windows configuration missing: $configPath (copy config/windows.example.psd1 and edit it)"
}

$config = Import-PowerShellDataFile -LiteralPath $configPath
$instancePrefix = [string]$config.MonitorInstancePrefix
$pcInput = [string]$config.PcInput
$macInput = [string]$config.MacInput
if ($instancePrefix -notmatch '^DISPLAY\\[^\\]+\\$' -or $instancePrefix -match 'REPLACE_ME') {
    throw 'Set MonitorInstancePrefix in .local/config/windows.psd1 from your active WmiMonitorID InstanceName'
}
if ($pcInput -notmatch '^0x[0-9a-fA-F]{2}$' -or $macInput -notmatch '^0x[0-9a-fA-F]{2}$' -or $pcInput -eq $macInput) {
    throw 'Set two distinct two-digit PcInput and MacInput VCP values in .local/config/windows.psd1'
}
$pcInput = $pcInput.ToLowerInvariant()
$macInput = $macInput.ToLowerInvariant()

function Invoke-MonitorSwitch {
    param([string[]]$Arguments)

    $output = @(& $cli @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "monitor-switch $($Arguments -join ' ') failed: $($output -join ' | ')"
    }
    return $output
}

function Get-InputValue {
    param([string]$Selector)

    $output = Invoke-MonitorSwitch -Arguments @('current', '--display', $Selector)
    $match = [regex]::Match(($output -join "`n"), 'current input source:\s*(0x[0-9a-fA-F]+)')
    if (-not $match.Success) {
        throw "Unable to parse input source: $($output -join ' | ')"
    }
    return $match.Groups[1].Value.ToLowerInvariant()
}

$displays = @(Invoke-MonitorSwitch -Arguments @('displays') | Where-Object { $_ })
if ($displays.Count -ne 1) {
    throw "Expected one DDC display, found $($displays.Count); refusing to select an input"
}
$fields = $displays[0] -split "`t"
if ($fields.Count -lt 3 -or $fields[0] -ne '1' -or [string]::IsNullOrWhiteSpace($fields[2])) {
    throw "Unexpected display listing: $($displays[0])"
}
$selector = $fields[2]

$active = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID | Where-Object Active)
if ($active.Count -ne 1 -or -not $active[0].InstanceName.StartsWith($instancePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Active Windows monitor is not the single configured $instancePrefix display; refusing to select an input"
}

$current = Get-InputValue -Selector $selector
if ($Command -eq 'status') {
    Write-Output "input=$current selector=$selector"
    return
}

if ($current -eq $macInput) {
    Write-Output "Mac input is already selected ($current); no write sent"
    return
}
if ($current -ne $pcInput) {
    throw "Expected Windows input $pcInput, got $current; refusing to select an input"
}
if ($DryRun) {
    Write-Output "would send one VCP 0x60=$macInput to $selector"
    return
}
if ($config.SwitchingEnabled -ne $true) {
    throw 'SwitchingEnabled is false in .local/config/windows.psd1; status and dry-run remain available'
}

[void](Invoke-MonitorSwitch -Arguments @('raw', $macInput, '--display', $selector))
for ($attempt = 1; $attempt -le 4; $attempt++) {
    Start-Sleep -Seconds 1
    try {
        $after = Get-InputValue -Selector $selector
        if ($after -eq $macInput) {
            Write-Output "Mac input selected ($macInput). If the picture is dark, move the shared mouse or press a key to wake the Mac display."
            return
        }
    }
    catch {
        # DDC read may be temporarily unavailable during an input transition.
    }
}
throw "Input write sent once, but $macInput was not confirmed by read-back; inspect the monitor before retrying"
