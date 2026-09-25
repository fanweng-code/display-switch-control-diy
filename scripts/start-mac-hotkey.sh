#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/.local/Display Switch Hotkey.app"

if [ ! -x "$APP/Contents/MacOS/DisplaySwitchHotkey" ]; then
    "$ROOT/scripts/build-mac-hotkey.sh"
fi
open "$APP"
echo "Started Display Switch Hotkey; look for ⇄ in the menu bar. Log: $ROOT/.local/logs/mac-hotkey.log"
