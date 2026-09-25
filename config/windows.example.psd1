@{
    # Copy to .local/config/windows.psd1. Use your active WmiMonitorID prefix.
    MonitorInstancePrefix = 'DISPLAY\REPLACE_ME\'

    # Read your own VCP 0x60 values with Monitor Switch before enabling writes.
    PcInput = '0x00'
    MacInput = '0x00'
    SwitchingEnabled = $false
}
