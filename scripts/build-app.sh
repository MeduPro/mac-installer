#!/bin/bash
# Baut Tomato-Installer.app (Universal: Apple Silicon + Intel), signiert ad-hoc
# und erzeugt Zip und DMG zum Verteilen.
#
#   scripts/build-app.sh            → dist/Tomato-Installer.app, .zip, .dmg
#
# Ohne Apple-Developer-ID: Ad-hoc-Signatur ist auf Apple Silicon Pflicht, damit die
# App überhaupt startet. Gatekeeper fragt beim ersten Öffnen trotzdem nach (siehe README).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
DIST="$ROOT/dist"
APP="$DIST/Tomato-Installer.app"
NAME="Tomato-Installer-$VERSION"

echo "▸ Tests"
swift test --quiet

echo "▸ Kompilieren (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64 --quiet
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/TomatoInstaller"

echo "▸ App-Paket"
rm -rf "$APP" "$DIST/$NAME.zip" "$DIST/$NAME.dmg"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TomatoInstaller"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE NOTICE "$APP/Contents/Resources/"

echo "▸ Ad-hoc-Signatur"
codesign --force --sign - --options runtime --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "▸ Zip und DMG"
ditto -c -k --keepParent "$APP" "$DIST/$NAME.zip"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
cp README.md "$STAGE/Bitte lesen.md"
hdiutil create -quiet -volname "Tomato-Installer $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DIST/$NAME.dmg"
rm -rf "$STAGE" "$(dirname "$ICONSET")"

(cd "$DIST" && shasum -a 256 "$NAME.zip" "$NAME.dmg" > "$NAME.sha256")
echo "✓ Fertig: $DIST"
ls -lh "$DIST" | tail -n +2
