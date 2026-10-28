#!/bin/bash
# Concierge Ucho - builds and signs the Android app without Gradle (aapt2, javac, d8, apksigner); optional "install" pushes it to the phone over adb.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
SDK="${ANDROID_SDK:-/usr/local/share/android-commandlinetools}"
BT="$SDK/build-tools/35.0.0"
JAR="$SDK/platforms/android-34/android.jar"
OUT="$ROOT/Niepotrzebne/ear-build"
KS="$ROOT/Niepotrzebne/ear.keystore"
VERSION="${VERSION:-1}"

rm -rf "$OUT"
mkdir -p "$OUT/classes" "$OUT/gen"
"$BT/aapt2" compile --dir res -o "$OUT/res.zip"
"$BT/aapt2" link -o "$OUT/base.apk" -I "$JAR" --manifest AndroidManifest.xml "$OUT/res.zip" --java "$OUT/gen" \
  --min-sdk-version 26 --target-sdk-version 34 --version-code "$VERSION" --version-name "1.$VERSION"
javac --release 17 -nowarn -classpath "$JAR" -d "$OUT/classes" $(find src "$OUT/gen" -name '*.java')
"$BT/d8" --release --lib "$JAR" --min-api 26 --output "$OUT" $(find "$OUT/classes" -name '*.class')
(cd "$OUT" && cp base.apk unsigned.apk && zip -q unsigned.apk classes.dex)
"$BT/zipalign" -f 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"
if [ ! -f "$KS" ]; then
  keytool -genkeypair -keystore "$KS" -storepass gzowo-ear -keypass gzowo-ear -alias ear -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Gzowo Concierge" >/dev/null 2>&1
fi
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:gzowo-ear --key-pass pass:gzowo-ear --out "$OUT/ConciergeUcho.apk" "$OUT/aligned.apk"
echo "built: $OUT/ConciergeUcho.apk"

if [ "${1:-}" = "install" ]; then
  PKG=fun.gzowo.concierge.ear
  adb install -r "$OUT/ConciergeUcho.apk"
  adb shell pm grant $PKG android.permission.RECORD_AUDIO
  adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS
  adb shell dumpsys deviceidle whitelist +$PKG >/dev/null
  adb shell am start -n $PKG/.MainActivity
fi
