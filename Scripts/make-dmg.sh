#!/usr/bin/env bash
#
# Packt .build/export/Anvil.app in ein DMG mit Programme-Verknüpfung.
#
#   ./Scripts/make-dmg.sh [version]
#
# Ohne Version wird die MARKETING_VERSION aus dem Projekt genommen.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/.build/export/Anvil.app"
[ -d "$APP" ] || { echo "Es gibt kein $APP — erst ./Scripts/archive.sh laufen lassen." >&2; exit 1; }

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
DMG="$ROOT/.build/Anvil-$VERSION.dmg"
STAGE="$ROOT/.build/dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Anvil.app"
ln -s /Applications "$STAGE/Programme"

echo "==> DMG bauen"
hdiutil create \
    -volname "Anvil $VERSION" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -quiet \
    "$DMG"

rm -rf "$STAGE"

echo "==> fertig: $DMG"
shasum -a 256 "$DMG"
