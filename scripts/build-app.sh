#!/bin/zsh
# Builds build/Hyaline.app, signed ad hoc. Set SIGN_IDENTITY to a certificate's name to
# sign with it, VERSION and BUILD to stamp the version, and CONFIG=debug for a debug
# build (which includes the self-checks).
set -euo pipefail
cd "${0:A:h:h}"

version=${VERSION:-0.1.0}
build=${BUILD:-1}
config=${CONFIG:-release}

./scripts/make-icon.sh >/dev/null
swift build -c "$config" --product Hyaline

app=build/Hyaline.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp ".build/$config/Hyaline" "$app/Contents/MacOS/"
cp build/AppIcon.icns "$app/Contents/Resources/"

cat >"$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Hyaline</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.bonevane.hyaline</string>
    <key>CFBundleName</key><string>Hyaline</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$build</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSCalendarsFullAccessUsageDescription</key><string>Hyaline shows your upcoming events in its calendar widgets.</string>
    <key>NSRemindersFullAccessUsageDescription</key><string>Hyaline shows your reminders and lets you tick them off from the widget.</string>
    <key>NSLocationUsageDescription</key><string>Hyaline uses your location for local weather and sunrise and sunset times.</string>
    <key>NSLocationWhenInUseUsageDescription</key><string>Hyaline uses your location for local weather and sunrise and sunset times.</string>
    <key>NSAppleEventsUsageDescription</key><string>Hyaline reads what Spotify or Music is playing and controls playback from the Now Playing widget.</string>
</dict>
</plist>
PLIST

identity=${SIGN_IDENTITY:--}
# A real certificate gets a secure timestamp, which notarization requires.
timestamp=()
[[ $identity != - ]] && timestamp=(--timestamp)
codesign --force --options runtime $timestamp --entitlements Resources/Hyaline.entitlements --sign "$identity" "$app"
print "Built $app"
