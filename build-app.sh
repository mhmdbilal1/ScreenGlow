#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/ScreenGlow.app"
swift build --package-path "$ROOT" -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/ScreenGlow" "$APP/Contents/MacOS/ScreenGlow"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT/Resources/app-icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  sips -z "$double_size" "$double_size" "$ROOT/Resources/app-icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ScreenGlow</string>
  <key>CFBundleIdentifier</key><string>com.screenglow.app</string>
  <key>CFBundleName</key><string>ScreenGlow</string>
  <key>CFBundleDisplayName</key><string>ScreenGlow</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSBluetoothAlwaysUsageDescription</key><string>ScreenGlow uses Bluetooth to find and control your Lotus Lantern light strip.</string>
  <key>NSScreenCaptureUsageDescription</key><string>ScreenGlow samples the colors on your display so your light strip can match them.</string>
  <key>NSLocalNetworkUsageDescription</key><string>ScreenGlow connects to your Home Assistant instance on your local network to control Cync bulbs.</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
# Finder and file-provider metadata can invalidate a local bundle signature;
# strip it before applying the stable ad-hoc signature.
xattr -cr "$APP"
# Keep a stable ad-hoc designated requirement so macOS privacy permissions survive
# rebuilds of this locally built app while its bundle identifier stays the same.
codesign --force --deep --sign - --requirements '=designated => identifier "com.screenglow.app"' "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
