#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
UPSTREAM='https://github.com/chikacya/monitor-switch.git'
PIN='d5614ea37f9e53fcaa8b233221fdf600d8b71b6f'

if [ -n "${MONITOR_SWITCH_SOURCE_DIR:-}" ]; then
    SOURCE=$MONITOR_SWITCH_SOURCE_DIR
    TEMP=''
else
    TEMP=$(mktemp -d)
    trap 'rm -rf "$TEMP"' EXIT HUP INT TERM
    SOURCE="$TEMP/source"
    git clone -q "$UPSTREAM" "$SOURCE"
    git -C "$SOURCE" checkout -q --detach "$PIN"
fi

ACTUAL=$(git -C "$SOURCE" rev-parse HEAD)
if [ "$ACTUAL" != "$PIN" ]; then
    echo "error: Monitor Switch source is $ACTUAL, expected $PIN" >&2
    exit 1
fi

command -v cargo >/dev/null 2>&1 || {
    echo 'error: cargo is required (Homebrew: brew install rust)' >&2
    exit 1
}

TARGET=$(mktemp -d)
trap 'rm -rf "$TARGET"; if [ -n "$TEMP" ]; then rm -rf "$TEMP"; fi' EXIT HUP INT TERM
(cd "$SOURCE" && CARGO_TARGET_DIR="$TARGET" cargo build --locked --release --bin monitor-switch)
mkdir -p "$ROOT/.local/bin"
install -m 755 "$TARGET/release/monitor-switch" "$ROOT/.local/bin/monitor-switch"
echo "Installed pinned Monitor Switch CLI in $ROOT/.local/bin/monitor-switch"
