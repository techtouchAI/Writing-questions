#!/usr/bin/env bash
# Build a separate debug keyboard fixture using the installed Android SDK only.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:?Usage: build_acceptance_ime.sh OUTPUT_DIRECTORY}"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:?Android SDK required}}"
mkdir -p "$out"; out="$(cd "$out" && pwd)"
platform="$sdk/platforms/android-35/android.jar"
if [ ! -f "$platform" ] || [ ! -d "$sdk/build-tools/35.0.0" ]; then
  sdkmanager 'platforms;android-35' 'build-tools;35.0.0'
fi
bt="$sdk/build-tools/35.0.0"
fixture="$root/tool/android_ime_fixture"
mkdir -p "$out/gen" "$out/classes" "$out/dex"
"$bt/aapt2" compile --dir "$fixture/res" -o "$out/resources.zip"
"$bt/aapt2" link -I "$platform" --manifest "$fixture/AndroidManifest.xml" \
  --java "$out/gen" --min-sdk-version 23 --target-sdk-version 35 \
  -o "$out/unsigned.apk" "$out/resources.zip"
find "$fixture/src" "$out/gen" -name '*.java' > "$out/java-sources.txt"
javac -encoding UTF-8 -source 8 -target 8 -classpath "$platform" -d "$out/classes" @"$out/java-sources.txt"
find "$out/classes" -name '*.class' > "$out/class-files.txt"
"$bt/d8" --min-api 23 --lib "$platform" --output "$out/dex" @"$out/class-files.txt"
zip -j "$out/unsigned.apk" "$out/dex/classes.dex"
"$bt/zipalign" -f 4 "$out/unsigned.apk" "$out/aligned.apk"
if [ ! -f "$out/fixture.keystore" ]; then
  keytool -genkeypair -keystore "$out/fixture.keystore" -storepass android -keypass android \
    -alias fixture -dname 'CN=Test-only acceptance IME' -keyalg RSA -validity 3650
fi
"$bt/apksigner" sign --ks "$out/fixture.keystore" --ks-pass pass:android --key-pass pass:android \
  --out "$out/acceptance-ime.apk" "$out/aligned.apk"
"$bt/apksigner" verify "$out/acceptance-ime.apk"
sha256sum "$out/acceptance-ime.apk"
observer="$root/tool/android_automation_fixture"
mkdir -p "$out/observer-gen" "$out/observer-classes" "$out/observer-dex"
"$bt/aapt2" link -I "$platform" --manifest "$observer/AndroidManifest.xml" \
  --java "$out/observer-gen" --min-sdk-version 23 --target-sdk-version 35 \
  -o "$out/observer-unsigned.apk"
find "$observer/src" "$out/observer-gen" -name '*.java' > "$out/observer-sources.txt"
javac -encoding UTF-8 -source 8 -target 8 -classpath "$platform" \
  -d "$out/observer-classes" @"$out/observer-sources.txt"
find "$out/observer-classes" -name '*.class' > "$out/observer-classes.txt"
"$bt/d8" --min-api 23 --lib "$platform" --output "$out/observer-dex" @"$out/observer-classes.txt"
zip -j "$out/observer-unsigned.apk" "$out/observer-dex/classes.dex"
"$bt/zipalign" -f 4 "$out/observer-unsigned.apk" "$out/observer-aligned.apk"
"$bt/apksigner" sign --ks "$out/fixture.keystore" --ks-pass pass:android --key-pass pass:android \
  --out "$out/acceptance-automation.apk" "$out/observer-aligned.apk"
"$bt/apksigner" verify "$out/acceptance-automation.apk"
sha256sum "$out/acceptance-automation.apk"
