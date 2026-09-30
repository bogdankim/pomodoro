#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

# A stray SDKROOT pointing at the CommandLineTools SDK breaks the Xcode
# toolchain (compiler/SDK version skew); xcode-select owns the SDK choice.
unset SDKROOT

CONFIG="${1:-release}"
swift build -c "$CONFIG"

APP="build/Pomodoro.app"
BIN=".build/$CONFIG/Pomodoro"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pomodoro"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
