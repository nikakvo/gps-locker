#!/usr/bin/env bash
# GPS Locker - build the signed companion APK
#
# Output: dist/GPSLocker-v<version>-<HHMM>.apk, also copied to /mnt/d/Download
# The time suffix keeps every build name unique (Telegram caches files by name).
#
# Signing uses the shared personal keystore. The password is read from
# ~/keys/tears-gps.pass (chmod 600) if it exists, otherwise apksigner asks for it.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

SDK="${ANDROID_HOME:-$HOME/android-sdk}"
BUILD_TOOLS="$SDK/build-tools/36.0.0"
KEYSTORE="${KEYSTORE:-$HOME/keys/tears-gps.jks}"
KEY_ALIAS="${KEY_ALIAS:-tearsgps}"
PASS_FILE="${PASS_FILE:-$HOME/keys/tears-gps.pass}"
WIN_DOWNLOAD="/mnt/d/Download"

die() { echo "ERROR: $*" >&2; exit 1; }

[ -d "$SDK" ] || die "Android SDK not found at $SDK"
[ -x "$BUILD_TOOLS/apksigner" ] || die "build-tools 36.0.0 missing in $SDK"
[ -f "$KEYSTORE" ] || die "Keystore not found: $KEYSTORE"

echo "sdk.dir=$SDK" > local.properties

# Reuse the Gradle wrapper scripts from an existing project (same Gradle line)
if [ ! -x gradlew ]; then
    WRAP_SRC="$HOME/OpenHub"
    [ -f "$WRAP_SRC/gradlew" ] || die "No gradlew here and none in $WRAP_SRC"
    cp "$WRAP_SRC/gradlew" .
    cp "$WRAP_SRC/gradle/wrapper/gradle-wrapper.jar" gradle/wrapper/
    chmod +x gradlew
    echo "Gradle wrapper copied from $WRAP_SRC"
fi

VERSION=$(sed -n "s/.*versionName *= *'\(.*\)'.*/\1/p" app/build.gradle)
[ -n "$VERSION" ] || die "Could not read versionName"

echo "==> Building GPS Locker $VERSION"
./gradlew --no-daemon clean assembleRelease

UNSIGNED="app/build/outputs/apk/release/app-release-unsigned.apk"
[ -f "$UNSIGNED" ] || die "Unsigned APK not found: $UNSIGNED"

mkdir -p dist
OUT="dist/GPSLocker-v$VERSION-$(date +%H%M).apk"
ALIGNED="app/build/gpslocker-aligned.apk"

"$BUILD_TOOLS/zipalign" -f -p 4 "$UNSIGNED" "$ALIGNED"

echo "==> Signing with $KEYSTORE ($KEY_ALIAS)"
SIGN_ARGS=(--ks "$KEYSTORE" --ks-key-alias "$KEY_ALIAS")
if [ -f "$PASS_FILE" ]; then
    # Password stored once in a private file (chmod 600), no prompt
    # One file only: apksigner reuses the keystore password for the key
    SIGN_ARGS+=(--ks-pass "file:$PASS_FILE")
fi
"$BUILD_TOOLS/apksigner" sign "${SIGN_ARGS[@]}" --out "$OUT" "$ALIGNED"
"$BUILD_TOOLS/apksigner" verify "$OUT"
rm -f "$OUT.idsig"

echo "==> APK: $OUT ($(du -h "$OUT" | cut -f1))"

# ---------- Module zip ----------
command -v zip >/dev/null || die "zip is missing: sudo apt install zip"

MOD_VERSION=$(sed -n 's/^version=//p' module/module.prop)
STAGE="app/build/module-stage"
rm -rf "$STAGE"
cp -r module "$STAGE"
cp "$OUT" "$STAGE/GPSLocker.apk"
# shell scripts must keep LF line endings
find "$STAGE" -name '*.sh' -exec sed -i 's/\r$//' {} +

ZIP="dist/GPSLocker-$MOD_VERSION-$(date +%H%M).zip"
( cd "$STAGE" && zip -qr9 "../../../$ZIP" . -x '.*' )
echo "==> Module: $ZIP ($(du -h "$ZIP" | cut -f1))"

if [ -d "$WIN_DOWNLOAD" ]; then
    cp "$OUT" "$ZIP" "$WIN_DOWNLOAD/"
    echo "==> Copied to D:\\Download\\: $(basename "$OUT"), $(basename "$ZIP")"
fi
echo "==> Done"
