#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/.local/Display Switch Hotkey.app"
CONTENTS="$APP/Contents"

command -v clang >/dev/null 2>&1 || {
    echo 'error: clang is required (Xcode Command Line Tools)' >&2
    exit 1
}

mkdir -p "$CONTENTS/MacOS"
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>DisplaySwitchHotkey</string>
  <key>CFBundleIdentifier</key><string>com.example.display-switch-hotkey</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Display Switch Hotkey</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/display-switch-clang-cache" \
clang -fobjc-arc -O2 -framework AppKit -framework Carbon \
    "$ROOT/mac/DisplaySwitchHotkey.m" \
    -o "$CONTENTS/MacOS/DisplaySwitchHotkey"
codesign --force --sign - "$APP"
echo "Built $APP"
