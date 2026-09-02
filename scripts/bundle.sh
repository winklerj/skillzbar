#!/bin/bash
# Assemble SkillzBar.app from the SwiftPM release binary. No Xcode project needed.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=".build/release/SkillzBar"
APP="build/SkillzBar.app"
VERSION=$(grep -o 'skillzBarVersion = "[^"]*"' Sources/SkillzBarCore/Models.swift | cut -d'"' -f2)
[ -x "$BIN" ] || { echo "run 'swift build -c release' first" >&2; exit 1; }
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SkillzBar"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>SkillzBar</string>
  <key>CFBundleIdentifier</key><string>dev.robb.SkillzBar</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>SkillzBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
echo -n "APPL????" > "$APP/Contents/PkgInfo"
codesign --force --sign - --identifier dev.robb.SkillzBar "$APP" 2>&1 | grep -v "replacing existing signature" || true
echo "built $APP (v$VERSION)"
