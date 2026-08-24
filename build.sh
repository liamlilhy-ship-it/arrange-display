#!/bin/bash
# Builds DisplayManager.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/DisplayManager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp .build/release/DisplayManager "$APP/Contents/MacOS/DisplayManager"
cp -R .build/release/Sparkle.framework "$APP/Contents/Frameworks/"

# Sign inside-out: nested code first, container last.
#
# Deliberately no --options runtime. Hardened runtime turns on library
# validation, and an ad-hoc signed binary refuses to load an ad-hoc signed
# framework ("mapping process and mapped file have different Team IDs") —
# the app aborts in dyld at launch. Add --options runtime back only together
# with a real Developer ID, where app and framework share a Team ID.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for target in \
    "$SPARKLE/XPCServices/Downloader.xpc" \
    "$SPARKLE/XPCServices/Installer.xpc" \
    "$SPARKLE/Updater.app" \
    "$SPARKLE/Autoupdate" \
    "$APP/Contents/Frameworks/Sparkle.framework" \
    "$APP"; do
    codesign --force --sign - "$target"
done

echo "Built $APP"
