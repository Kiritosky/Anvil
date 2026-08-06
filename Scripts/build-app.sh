#!/usr/bin/env bash
#
# Builds Anvil.app from the SwiftPM executable.
#
# SwiftPM produces a bare Mach-O binary; macOS needs a bundle for the Info.plist
# (usage descriptions) and the entitlements (microphone, network, sandbox) to be
# honoured, so we assemble the bundle here and ad-hoc sign it.
#
#   ./Scripts/build-app.sh              -> debug build into .build/Anvil.app
#   ./Scripts/build-app.sh release      -> release build
#   ./Scripts/build-app.sh release --sign "Developer ID Application: ..."
#
set -euo pipefail

CONFIG="${1:-debug}"
shift || true

SIGN_IDENTITY="-"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign) SIGN_IDENTITY="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --product Anvil

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$BIN_DIR/Anvil.app"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/Anvil" "$APP/Contents/MacOS/Anvil"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# SwiftPM emits resource bundles next to the binary; carry them along so
# targets that add resources later keep working without touching this script.
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
done

# Translations. German is the source language and needs no .lproj — its strings
# are the keys — so only the other languages are copied. Without this step the
# app still runs, just always in German.
lproj_count=0
for lproj in "$ROOT"/Resources/*.lproj; do
    [ -d "$lproj" ] || continue
    cp -R "$lproj" "$APP/Contents/Resources/"
    lproj_count=$((lproj_count + 1))
done
echo "    $lproj_count Übersetzung(en) kopiert"

# Das Icon wird gezeichnet, nicht mitgeliefert: sieben Größen, ein paar
# Formen, und eine eingecheckte Binärdatei, die niemand vergleichen kann, ist
# genau der Weg, auf dem Icons still veralten.
ICON="$ROOT/.build/AppIcon.icns"
if [ ! -e "$ICON" ] || [ "$ROOT/Scripts/make-icon.swift" -nt "$ICON" ]; then
    echo "==> Icon zeichnen"
    swift "$ROOT/Scripts/make-icon.swift" "$ICON" || echo "    Icon konnte nicht erzeugt werden"
fi

if [ -e "$ICON" ]; then
    cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
    echo "    Icon eingebettet"
fi

echo "==> codesign ($SIGN_IDENTITY)"
codesign --force --sign "$SIGN_IDENTITY" \
    --entitlements "$ROOT/Resources/Anvil.entitlements" \
    --options runtime \
    --timestamp=none \
    "$APP" 2>&1 | sed 's/^/    /' || {
        echo "    codesign failed; the app will still run but microphone access may be denied" >&2
    }

echo "==> done: $APP"
echo "    open \"$APP\""
