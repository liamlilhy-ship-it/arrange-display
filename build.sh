#!/bin/bash
# Builds DisplayManager.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/DisplayManager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp .build/release/DisplayManager "$APP/Contents/MacOS/DisplayManager"
codesign --force --sign - "$APP"

echo "Built $APP"
