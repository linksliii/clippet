#!/bin/bash
# Builds Clippet.app from the SwiftPM package.
# Pure command-line toolchain: no Xcode project required.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="$ROOT/build/Clippet.app"
BIN="$ROOT/.build/$CONFIG/Clippet"

echo "==> building ($CONFIG)"
swift build -c "$CONFIG" 2>&1 | grep -vE "xcrun:|XCTest|^\s*$" || true

if [[ ! -f "$BIN" ]]; then
    echo "error: binary missing at $BIN" >&2
    exit 1
fi

echo "==> assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Clippet"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Drop local symbols before signing: halves the binary with no behavioural
# change. Must happen before codesign or the signature breaks.
strip -x "$APP/Contents/MacOS/Clippet" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Clippet</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.clippet</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>Clippet</string>
    <key>CFBundleDisplayName</key>
    <string>Clippet</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" 2>&1 | tail -2

echo "==> done: $APP"
