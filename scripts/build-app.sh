#!/bin/bash
# Builds HouseCleaning.app into ./build. Usage: scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID="${BUNDLE_ID:-com.housecleaning.HouseCleaning}"
VERSION="${VERSION:-1.0.0}"
APP="build/HouseCleaning.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/HouseCleaning" "$APP/Contents/MacOS/HouseCleaning"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>HouseCleaning</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleName</key>
	<string>HouseCleaning</string>
	<key>CFBundleDisplayName</key>
	<string>HouseCleaning</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS can remember the Full Disk Access grant.
codesign --force --sign - "$APP"

echo "Built $APP"
