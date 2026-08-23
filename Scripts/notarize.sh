#!/usr/bin/env bash
#
# Schickt ein DMG zur Beglaubigung und heftet das Ticket an.
#
#   ./Scripts/notarize.sh .build/Anvil-1.0.0.dmg
#
# Erwartet in der Umgebung:
#   NOTARY_APPLE_ID       Apple-ID des Entwicklerkontos
#   NOTARY_TEAM_ID        Team-ID
#   NOTARY_PASSWORD       app-spezifisches Passwort
#
# Ohne diese drei bricht das Skript mit Hinweis ab statt still nichts zu tun:
# ein Release, das unbeglaubigt durchrutscht, fällt erst beim Nutzer auf.

set -euo pipefail

DMG="${1:-}"
[ -f "$DMG" ] || { echo "Nutzung: $0 <pfad.dmg>" >&2; exit 2; }

for var in NOTARY_APPLE_ID NOTARY_TEAM_ID NOTARY_PASSWORD; do
    if [ -z "${!var:-}" ]; then
        echo "$var fehlt — ohne Developer-ID-Konto lässt sich nicht beglaubigen." >&2
        exit 1
    fi
done

echo "==> Beglaubigung einreichen"
xcrun notarytool submit "$DMG" \
    --apple-id "$NOTARY_APPLE_ID" \
    --team-id "$NOTARY_TEAM_ID" \
    --password "$NOTARY_PASSWORD" \
    --wait

echo "==> Ticket anheften"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> beglaubigt: $DMG"
