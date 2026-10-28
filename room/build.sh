#!/bin/bash
# Concierge Pokój - builds the room app for MacPetite (Intel, macOS 12) with the Vosk library, the Polish model and the sounds.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
VENDOR="$ROOT/Niepotrzebne/room-vendor"
OUT="$ROOT/Niepotrzebne/room-build"
APP="$OUT/Concierge Pokój.app"

mkdir -p "$VENDOR"
if [ ! -f "$VENDOR/vosk-osx-0.3.42/libvosk.dylib" ]; then
  curl -sL -o "$VENDOR/vosk-osx.zip" https://github.com/alphacep/vosk-api/releases/download/v0.3.42/vosk-osx-0.3.42.zip
  (cd "$VENDOR" && unzip -q -o vosk-osx.zip)
fi
if [ ! -d "$VENDOR/vosk-model-small-pl-0.22" ]; then
  curl -sL -o "$VENDOR/model-pl.zip" https://alphacephei.com/vosk/models/vosk-model-small-pl-0.22.zip
  (cd "$VENDOR" && unzip -q -o model-pl.zip)
fi

ORT="$VENDOR/ort/onnxruntime-osx-x86_64-1.17.3"
if [ ! -f "$ORT/lib/libonnxruntime.1.17.3.dylib" ]; then
  mkdir -p "$VENDOR/ort"
  curl -sL -o "$VENDOR/ort/ort.tgz" https://github.com/microsoft/onnxruntime/releases/download/v1.17.3/onnxruntime-osx-x86_64-1.17.3.tgz
  (cd "$VENDOR/ort" && tar xzf ort.tgz)
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp "$VENDOR/vosk-osx-0.3.42/libvosk.dylib" "$APP/Contents/Frameworks/"
install_name_tool -id @rpath/libvosk.dylib "$APP/Contents/Frameworks/libvosk.dylib"
cp "$ORT/lib/libonnxruntime.1.17.3.dylib" "$APP/Contents/Frameworks/"
cp -R Resources/sounds "$APP/Contents/Resources/sounds"
cp Resources/wake-words.txt "$APP/Contents/Resources/"
[ -d Resources/oww ] && cp -R Resources/oww "$APP/Contents/Resources/oww"
rsync -a --exclude README "$VENDOR/vosk-model-small-pl-0.22/" "$APP/Contents/Resources/model/"

swiftc -O -swift-version 5 -target x86_64-apple-macosx12.0 \
  -import-objc-header Bridging.h -Xcc -IVosk -Xcc -I"$ORT/include" \
  -L "$APP/Contents/Frameworks" -lvosk "$APP/Contents/Frameworks/libonnxruntime.1.17.3.dylib" \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  Sources/*.swift -o "$APP/Contents/MacOS/ConciergeRoom"

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -p codesigning 2>/dev/null | grep -o '"[^"]*Local Signing"' | head -1 | tr -d '"')}"
IDENTITY="${IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/libvosk.dylib"
codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/libonnxruntime.1.17.3.dylib"
codesign --force --sign "$IDENTITY" --identifier fun.gzowo.concierge.room "$APP"
echo "built: $APP"
