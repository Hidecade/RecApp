#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP=${APP_PATH:-$ROOT/dist/RecApp.app}

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/RecApp" "$APP/Contents/MacOS/RecApp"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/RecApp.icns" "$APP/Contents/Resources/RecApp.icns"
chmod +x "$APP/Contents/MacOS/RecApp"
codesign --force --deep --sign - "$APP"

echo "$APP"
