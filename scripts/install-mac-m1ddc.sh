#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
UPSTREAM='https://github.com/waydabber/m1ddc.git'
PIN='04d949794102eb8df01ad3681afff6464a3eede2'

if [ -n "${M1DDC_SOURCE_DIR:-}" ]; then
    SOURCE=$M1DDC_SOURCE_DIR
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
    echo "error: m1ddc source is $ACTUAL, expected $PIN" >&2
    exit 1
fi

command -v make >/dev/null 2>&1 || {
    echo 'error: make is required (Xcode Command Line Tools)' >&2
    exit 1
}

CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/display-switch-clang-cache" make -C "$SOURCE" binary
mkdir -p "$ROOT/.local/bin"
install -m 755 "$SOURCE/m1ddc" "$ROOT/.local/bin/m1ddc"
echo "Installed pinned m1ddc CLI in $ROOT/.local/bin/m1ddc"
