#!/usr/bin/env bash
# Build and launch Anvil.app, streaming its log output to this terminal.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-debug}"

"$ROOT/Scripts/build-app.sh" "$CONFIG"

APP="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)/Anvil.app"
exec "$APP/Contents/MacOS/Anvil"
