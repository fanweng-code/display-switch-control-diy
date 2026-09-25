# Display Switch Control

Source-first, local DDC/CI input switching between a Windows PC and an Apple Silicon Mac sharing one monitor and its USB hub/KVM. Each host runs a small background hotkey app that selects the other host's video input. There is no server or cloud dependency.

This is a **DIY reference project**, not a universal monitor driver or a ready-made installer. Fork it, measure your own display's input values, and keep your device identifiers in the ignored `.local/` directory. The original setup used an MSI MPG 321URX QD-OLED, a Mac Studio through an ASUS DC510 dock on USB-C, and a Windows PC on DisplayPort. Other monitor, dock, firmware, and sleep combinations need their own validation.

## What is included

| Host | User action | Command path |
| --- | --- | --- |
| Windows | `Ctrl+Alt+Shift+M` or **Switch to Mac** in the apple tray icon | AutoHotkey v2 → PowerShell → Monitor Switch → VCP `0x60` |
| Mac | `Control+Command+Shift+M` or `Control+Option+Shift+M`, or **Switch to PC** in the menu bar | AppKit/Carbon app → shell wrapper → m1ddc → VCP `0x60` |

Monitor Switch also discovers displays and reads the active input on both hosts. The apps reject overlapping presses and apply a five-second cooldown. A successful DDC read-back confirms the monitor's reported input value; it does not prove that a picture or USB peripherals are ready.

The Mac wrapper deliberately refuses a Mac-originated switch *to* the Mac input because that direction produced a black picture in the original setup. The intended round trip is Mac → PC from the Mac app, then PC → Mac from the Windows app. Always keep the monitor's on-screen input menu available as a fallback.

## Before you fork and run it

- Use an external display with DDC/CI enabled. Your source values are monitor-specific. Do not copy VCP values from an unrelated monitor.
- Connect both video paths and, if you want shared keyboard/mouse, connect the monitor's USB upstream paths for both hosts. Set its KVM behavior for your wiring.
- The current commands require exactly **one DDC display** and one active target display on Windows. They stop when discovery is ambiguous.
- Windows needs PowerShell, Git, Rust/Cargo to build Monitor Switch, and the portable AutoHotkey v2 executable.
- The Mac path needs Apple Silicon, Git, Rust/Cargo, and Xcode Command Line Tools for `clang`/`make`. [m1ddc](https://github.com/waydabber/m1ddc) documents its Apple Silicon requirement.
- Neither third-party binary nor your local configuration is committed. The source install scripts pin upstream revisions.

Click **Fork** on GitHub, then clone **your fork** on each host. Replace `YOUR_NAME` below:

~~~sh
git clone https://github.com/YOUR_NAME/display-switch-control-diy.git
cd display-switch-control-diy
~~~

On Windows, use the equivalent PowerShell commands. Keep the checkout at a stable path if you install Windows login startup; the shortcut points to that checkout.

## 1. Discover your monitor's inputs

Input selection is DDC/CI VCP `0x60`. On the original MSI unit, Windows DisplayPort read `0x0f` and Mac USB-C read `0x10`. Those are **observations from one unit**, not defaults for all displays. Confirm your own values while using the monitor's on-screen menu to select each input. Some hosts cannot query DDC while their input is inactive; use the host and connection that can read it.

Monitor Switch's `displays` command supplies the selector for `current`. Record the exact selector, the value shown for each input, and which host can still query the monitor after switching. Do not issue a raw write until you have a way to recover with the monitor's on-screen menu.

## 2. Windows setup

### Build the DDC command

From the root of your fork in PowerShell, with Git and Cargo available:

~~~powershell
$source = Join-Path $env:TEMP 'display-switch-monitor-switch-source'
git clone https://github.com/chikacya/monitor-switch.git $source
git -C $source checkout --detach d5614ea37f9e53fcaa8b233221fdf600d8b71b6f
cargo build --locked --release --bin monitor-switch --manifest-path (Join-Path $source 'Cargo.toml')
New-Item -ItemType Directory -Force .local\bin | Out-Null
Copy-Item (Join-Path $source 'target\release\monitor-switch.exe') .local\bin\monitor-switch.exe
~~~

Choose a different empty `$source` directory if that one already exists. Download the [official AutoHotkey v2 portable ZIP](https://www.autohotkey.com/download/2.0/) and copy its `AutoHotkey64.exe` to `.local\bin\AutoHotkey64.exe`. The original setup used v2.0.28; use v2, because the script is not compatible with v1.

Inspect the display and its current input:

~~~powershell
& .\.local\bin\monitor-switch.exe displays
& .\.local\bin\monitor-switch.exe current --display '<exact selector from displays>'
Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID |
  Where-Object Active | Select-Object InstanceName
~~~

Copy `config/windows.example.psd1` to `.local/config/windows.psd1`, then edit:

~~~powershell
New-Item -ItemType Directory -Force .local\config | Out-Null
Copy-Item config\windows.example.psd1 .local\config\windows.psd1
notepad .local\config\windows.psd1
~~~

`MonitorInstancePrefix` is the beginning of the active `InstanceName` through its final backslash, for example `DISPLAY\ABC1234\`. Set `PcInput` and `MacInput` to the values you measured. Leave `SwitchingEnabled = $false` until `status` and `-DryRun` both match your intended target:

~~~powershell
.\scripts\display-switch-windows.ps1 status
.\scripts\display-switch-windows.ps1 mac -DryRun
~~~

When the Mac is awake, the monitor's on-screen input controls work, and dry run names the right value, set `SwitchingEnabled = $true`. Make one controlled switch:

~~~powershell
.\scripts\display-switch-windows.ps1 mac
~~~

If a script execution policy blocks direct `.ps1` invocation, run it with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\display-switch-windows.ps1 mac`.

### Tray app and optional login startup

Start the apple tray app with `.\scripts\start-windows-hotkey.ps1`. It offers a disabled hotkey reminder, **Switch to Mac**, and **Exit**. Its log is `.local/logs/windows-hotkey.log`. To start it after you log in to Windows, run `.\scripts\install-windows-startup.ps1`. To remove that current-user startup shortcut, run `.\scripts\install-windows-startup.ps1 -Remove`. Reinstall the shortcut if you move the checkout.

The default hotkey is `Ctrl+Alt+Shift+M` in `scripts/display-switch-windows.ahk`. Change the AutoHotkey binding in your fork if that key combination conflicts with another app.

## 3. Mac setup

Install Xcode Command Line Tools if needed (`xcode-select --install`), and make `cargo` available. From the root of your fork:

~~~sh
./scripts/install-mac-backend.sh
./scripts/install-mac-m1ddc.sh
./.local/bin/monitor-switch displays
./.local/bin/m1ddc display list detailed
~~~

The install scripts build pinned upstream source into ignored `.local/bin/`. Use Monitor Switch's `displays` and `current --display '<exact selector>'` to record your input values. The `m1ddc display list detailed` output supplies the display UUID used by m1ddc; keep it local. The decimal `PC_M1DDC_VALUE` must represent the same input as `PC_VCP` (for example, `0x0f` is decimal `15`).

Create the local configuration:

~~~sh
mkdir -p .local/config
cp config/mac.example.conf .local/config/mac.conf
nano .local/config/mac.conf
./scripts/display-switch status
~~~

Set `DISPLAY_SELECTOR` to the exact Monitor Switch display name, `MAC_VCP` and `PC_VCP` to measured values, `M1DDC_DISPLAY_UUID` to the UUID reported by m1ddc, and `PC_M1DDC_VALUE` to the decimal PC input. Leave `SWITCHING_ENABLED='0'` until `status` reports the correct current input. When you can recover through the monitor's on-screen menu, change it to `'1'` and make one controlled `./scripts/display-switch pc` test.

Build and start the menu bar app:

~~~sh
./scripts/build-mac-hotkey.sh
./scripts/start-mac-hotkey.sh
~~~

The `⇄` menu bar item provides **Switch to PC**, **Check Keys…**, **Open Log**, and **Quit Display Switch**. It registers `Control+Command+Shift+M` and `Control+Option+Shift+M` because the physical Alt key can map differently on macOS. Use **Check Keys…** to see what your keyboard sends; adjust `RegisterEventHotKey` in `mac/DisplaySwitchHotkey.m` and rebuild if needed. The Mac app is started for the current login session; this project does not install a Mac login item.

## If switching fails

1. Use the monitor's on-screen menu to restore the input that displays a picture. Avoid repeated blind writes.
2. Check DDC/CI, cables, dock, USB upstream/KVM wiring, and whether the destination host has an active display signal. A sleeping display may briefly show **No Signal**; move the shared mouse or press a key.
3. Run `status` and recheck the exact selector, input values, display UUID, and enabled flag in your ignored local config.
4. Read `.local/logs/windows-hotkey.log` or `.local/logs/mac-hotkey.log` for key delivery and command results. A zero exit code or matching DDC read-back alone does not verify the picture or keyboard/mouse.
5. If more than one DDC display is connected, adapt the one-display guard in your fork before testing writes.

## Privacy and license

Only template configuration is committed. `.local/` is ignored and should hold your executable builds, device identifiers, and logs. Check your own fork before committing changes; monitor UUIDs, display serials, account paths, and test logs can reveal details of your setup.

This project's source is MIT licensed; see [LICENSE](LICENSE). It invokes, but does not redistribute, [Monitor Switch](https://github.com/chikacya/monitor-switch) and [m1ddc](https://github.com/waydabber/m1ddc). Review their licenses if you distribute compiled binaries.
