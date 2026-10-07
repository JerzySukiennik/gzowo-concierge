#!/bin/zsh
# Gzowo Concierge for macOS - builds Concierge.app (Swift, AppKit + WebKit + SwiftUI) and installs it to /Applications.
set -e
cd "$(dirname "$0")"
APP="build/Gzowo Concierge.app"
ARCH="$(uname -m)"
rm -rf build && mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ -f ../web/icon-1024.png ]; then python3 icon/make_icon_from_art.py ../web/icon-1024.png build/icon; else python3 icon/make_icon.py build/icon; fi
swiftc -O -swift-version 5 -target "$ARCH-apple-macosx26.0" Sources/*.swift -o "$APP/Contents/MacOS/Concierge"
cp Info.plist "$APP/Contents/Info.plist"
cp build/icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign -s - --force --deep --identifier fun.gzowo.concierge.mac "$APP"
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x Concierge 2>/dev/null || true
sleep 0.5
rm -rf "$DEST/Gzowo Concierge.app"
ditto "$APP" "$DEST/Gzowo Concierge.app"
echo "installed: $DEST/Gzowo Concierge.app"
