#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "Building..."
swift build -c release 2>&1

APP="FileBox.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/FileBox "$APP/Contents/MacOS/FileBox"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>      <string>FileBox</string>
    <key>CFBundleIdentifier</key>     <string>com.jakob.filebox</string>
    <key>CFBundleName</key>           <string>FileBox</string>
    <key>CFBundlePackageType</key>    <string>APPL</string>
    <key>CFBundleVersion</key>        <string>1</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>LSMinimumSystemVersion</key> <string>13.0</string>
    <key>LSUIElement</key>            <true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>FileBox uses Apple Events to read the current Finder selection.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>FileBox adds screenshots you take to the shelf automatically.</string>
</dict>
</plist>
PLIST

echo "Done — FileBox.app is ready."
echo "Drag it to /Applications to install, or just double-click to run."
open "$APP"
