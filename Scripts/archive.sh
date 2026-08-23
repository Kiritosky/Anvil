#!/usr/bin/env bash
#
# Baut Anvil.app aus dem Xcode-Projekt.
#
#   ./Scripts/archive.sh                    # Release, ad-hoc signiert
#   ./Scripts/archive.sh --config Debug
#   ./Scripts/archive.sh --identity "Developer ID Application: Name (TEAMID)"
#
# Ohne Developer-ID wird ad-hoc signiert. Die App läuft dann, Gatekeeper
# meldet sich aber beim ersten Start — siehe docs/DISTRIBUTION.md.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="Release"
IDENTITY="${ANVIL_SIGNING_IDENTITY:--}"
TEAM_ID="${ANVIL_TEAM_ID:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG="$2"; shift 2 ;;
        --identity) IDENTITY="$2"; shift 2 ;;
        --team) TEAM_ID="$2"; shift 2 ;;
        *) echo "unbekanntes Argument: $1" >&2; exit 2 ;;
    esac
done

OUT="$ROOT/.build/export"
ARCHIVE="$ROOT/.build/Anvil.xcarchive"
APP="$OUT/Anvil.app"

rm -rf "$ARCHIVE" "$OUT"
mkdir -p "$OUT"

# Ein sicherer Zeitstempel ist Voraussetzung fürs Beglaubigen, aber er kostet
# einen Gang zu Apples Zeitserver. Eine Ad-hoc-Signatur lässt sich ohnehin
# nicht stempeln, also wird nur bei echter Identität danach gefragt.
if [ "$IDENTITY" = "-" ]; then
    SIGN_FLAGS="--timestamp=none"
else
    SIGN_FLAGS="--timestamp"
fi

echo "==> xcodebuild archive ($CONFIG, Identität: $IDENTITY)"
xcodebuild archive \
    -project Anvil.xcodeproj \
    -scheme Anvil \
    -configuration "$CONFIG" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="$SIGN_FLAGS" \
    | grep -E '^(\*\*|.*error:)' || true

if [ ! -d "$ARCHIVE/Products/Applications/Anvil.app" ]; then
    echo "Archiv enthält keine App — Build fehlgeschlagen." >&2
    exit 1
fi

# Kein -exportArchive: der Export verlangt ein Team und ein Profil, und ohne
# Developer-ID gibt es beides nicht. Die App aus dem Archiv zu kopieren
# liefert dasselbe Bundle.
cp -R "$ARCHIVE/Products/Applications/Anvil.app" "$APP"

echo "==> codesign prüfen"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Signature|TeamIdentifier' | sed 's/^/    /'

echo "==> fertig: $APP"
