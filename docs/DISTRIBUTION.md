# Bauen und ausliefern

Anvil ist ein Xcode-Projekt (`Anvil.xcodeproj`) mit einem App-Target, das die
Module als lokales Swift-Paket einbindet. Das Paket beschreibt die
Bibliotheken und die Tests, Xcode das Bundle.

```
Anvil.xcodeproj      App-Target: Info.plist, Entitlements, Asset-Katalog, Version
Package.swift        AnvilKit, AnvilUI, AnvilAI, AnvilSpeech, AnvilToolbox + Tests
Sources/AnvilApp/    gehört dem App-Target, nicht dem Paket
```

## Bauen

```sh
swift test                          # Bibliotheken
./Scripts/run.sh                    # bauen und starten
./Scripts/archive.sh                # Release-Bundle nach .build/export/Anvil.app
./Scripts/make-dmg.sh               # DMG nach .build/Anvil-<version>.dmg
```

Das App-Icon wird gezeichnet, nicht gemalt:

```sh
swift Scripts/make-icon.swift       # schreibt Resources/Assets.xcassets/AppIcon.appiconset
```

Die PNGs sind eingecheckt, weil Xcode sie zur Bauzeit braucht. Die CI zeichnet
sie neu und vergleicht — laufen Skript und Katalog auseinander, fällt es auf.

## Version

Die Version steht in `MARKETING_VERSION` und `CURRENT_PROJECT_VERSION` im
Projekt; die `Info.plist` verweist nur darauf. Ein Release-Tag `v1.2.3` muss zu
`MARKETING_VERSION = 1.2.3` passen, sonst bricht der Workflow ab.

## Signieren

Ohne Developer-ID wird ad-hoc signiert. Die App läuft, aber Gatekeeper meldet
sich beim ersten Start; der Umweg steht in der Release-Beschreibung.

Mit Developer-ID:

```sh
./Scripts/archive.sh --identity "Developer ID Application: Name (TEAMID)" --team TEAMID
./Scripts/make-dmg.sh
NOTARY_APPLE_ID=… NOTARY_TEAM_ID=… NOTARY_PASSWORD=… ./Scripts/notarize.sh .build/Anvil-1.0.0.dmg
```

Hardened Runtime ist an, App Sandbox aus — Anvil geht nicht in den App Store
und braucht freien Zugriff auf Dateien, Git-Repos und lokale Prozesse.

## Veröffentlichen

Ein Tag `v*` startet `.github/workflows/release.yml`. Der Workflow prüft die
Version, testet, baut, packt ein DMG und legt ein Release an.

Ausprobieren, ohne etwas zu veröffentlichen: den Workflow von Hand starten
(`workflow_dispatch`) mit `dry_run: true`.

### Secrets

Alle optional. Fehlt eines, fällt der Workflow auf die nächstschwächere
Stufe zurück — ad-hoc statt Developer ID, unbeglaubigt statt beglaubigt.

| Secret | Wofür |
| --- | --- |
| `SIGNING_CERTIFICATE_P12` | Developer-ID-Zertifikat als Base64 (`base64 -i cert.p12`) |
| `SIGNING_CERTIFICATE_PASSWORD` | Passwort des `.p12` |
| `SIGNING_IDENTITY` | z. B. `Developer ID Application: Name (TEAMID)` |
| `APPLE_TEAM_ID` | Team-ID |
| `NOTARY_APPLE_ID` | Apple-ID des Entwicklerkontos |
| `NOTARY_TEAM_ID` | Team-ID fürs Beglaubigen |
| `NOTARY_PASSWORD` | app-spezifisches Passwort |
