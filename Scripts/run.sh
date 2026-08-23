#!/usr/bin/env bash
# Baut Anvil und startet es; die Logausgabe läuft in dieses Terminal.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-Debug}"

xcodebuild \
    -project Anvil.xcodeproj \
    -scheme Anvil \
    -configuration "$CONFIG" \
    -destination 'platform=macOS' \
    build \
    | grep -E '^(\*\*|.*(error|warning):)' || true

BUILT="$(xcodebuild -project Anvil.xcodeproj -scheme Anvil -configuration "$CONFIG" \
    -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"

exec "$BUILT/Anvil.app/Contents/MacOS/Anvil"
