#!/bin/bash
# Packages the app as a drag-to-install DMG: the mounted volume shows
# DisplayManager.app next to an Applications shortcut, plus a first-launch
# guide walking new users through the Gatekeeper approval.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
rm -rf build/dmg-staging build/ArrangeDisplay.dmg
mkdir -p build/dmg-staging
cp -R build/DisplayManager.app build/dmg-staging/
ln -s /Applications build/dmg-staging/Applications
cp docs/dmg/how-to-open.png "build/dmg-staging/How to Open.png"
hdiutil create -volname "Arrange Display" -srcfolder build/dmg-staging \
    -format UDZO -quiet build/ArrangeDisplay.dmg
rm -rf build/dmg-staging
echo "Built build/ArrangeDisplay.dmg"
