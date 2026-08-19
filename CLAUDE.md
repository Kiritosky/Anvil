# Anvil — Projektregeln

Anvil ist eine native macOS-App: eine erweiterbare Werkzeugsammlung für den
Alltag und fürs Entwickeln, mit KI-Funktionen auf Basis der Apple Foundation
Models (on-device) und optionalen externen Anbietern.

Repository (`Kiritosky/Anvil`), Produkt, Targets und Bundle-Identifier heißen
durchgehend **Anvil**. Nichts davon je wieder auf „Nook" zurückdrehen; wo noch
`nooktools` auftaucht, ist es ein Überbleibsel und gehört korrigiert.

## Commits

- **Keine Selbst-Verlinkung in Commits.** Commit-Messages, PR-Titel und
  PR-Beschreibungen enthalten **keine** `Co-Authored-By:`-Zeile, keinen
  `Claude-Session:`-Link, keinen „Generated with"-Footer und keine sonstige
  Erwähnung von Claude, Claude Code oder Modellnamen.
- Commit-Messages beschreiben nur die Änderung selbst, im Imperativ.

## Kommentare

- **Sparsam.** Ein Kommentar sagt, *warum* etwas so ist — nie, *was* dasteht.
- Doku über Typ oder Methode: ein kurzer Satz, höchstens zwei. Kein Aufsatz,
  keine Begründungskette, keine Anekdote.
- Im Rumpf einer Funktion in aller Regel gar keiner. Nur dort, wo eine Zeile
  ohne Hinweis nach einem Fehler aussieht.

## Distribution

- Die App geht **nicht** in den Mac App Store.
- **App Sandbox ist aus** (`com.apple.security.app-sandbox` wird nicht gesetzt).
  Tools dürfen frei aufs Dateisystem, auf Git-Repos und auf lokale Prozesse
  zugreifen. Signiert wird mit Hardened Runtime + Developer ID.
- Mikrofonzugriff läuft über TCC (`NSMicrophoneUsageDescription` in der
  `Info.plist`) plus das `com.apple.security.device.audio-input`-Entitlement,
  das die Hardened Runtime auch außerhalb der Sandbox verlangt.

## Architektur

| Target | Zweck |
| --- | --- |
| `AnvilKit` | Erweiterbarkeits-Kern: Tool-Modell, Registry, Kontext/DI, Storage |
| `AnvilUI` | Design-System: Tokens, Basis-Layouts, Komponentenbibliothek |
| `AnvilAI` | Sprachmodell-Abstraktion: Foundation Models + externe Anbieter |
| `AnvilSpeech` | Audioaufnahme und Transkription (`SpeechAnalyzer`) |
| `AnvilToolbox` | Die Tools selbst + generische Tool-Engines |
| `AnvilApp` | App-Shell: Fenster, Sidebar, Command-Palette, Einstellungen |

Abhängigkeiten zeigen immer nach unten. `AnvilKit` kennt weder KI noch Sprache
noch die App-Shell — dadurch bleibt der Kern austauschbar.

Testziele: `AnvilKitTests`, `AnvilUITests`, `AnvilToolboxTests`.

## Massenaktionen

Kein Werkzeug hört bei einem Element auf. Was für eine Datei geht, geht auch
für dreißig: Ziehen nimmt alle, der Dialog erlaubt Mehrfachauswahl, und die
Statuszeile sagt, wie viele es waren. Teure Schritte laufen schwungweise
nebenläufig statt einer nach dem anderen.

## Fremde Programme und Netz

- Alles, was ein Programm startet, geht über `ProcessRunner` — nie über eine
  Shell, immer mit Zeitgrenze.
- Geheimnisse (API-Schlüssel, GitHub-Token) liegen im Schlüsselbund, nie in
  Einstellungen oder Dateien. An `git` gehen sie über die Umgebung, nicht als
  Argument: Argumente stehen in der Prozessliste.
- Was Anvil klont oder herunterlädt, liegt im temporären Verzeichnis und wird
  wieder weggeräumt.

## UI-Regeln

- **Kein Tool baut eigenes Chrome.** Jede Tool-View sitzt in `ToolScaffold`
  (Header, Content, Inspector-Spalte, Header-Actions).
- Abstände, Radien, Farben, Schriften und Animationen kommen ausschließlich aus
  `AnvilSpacing`, `AnvilRadius`, `AnvilColor`, `AnvilFont`, `AnvilMotion`.
  Keine magischen Zahlen in Tool-Views.
- Optionen gehören in die Inspector-Spalte (`InspectorSection` + `OptionRow`),
  nicht verstreut in den Content.
- Fehler werden über `AnvilBanner` bzw. `.anvilErrorBanner(...)` gezeigt,
  niemals über Alerts oder `print`.
- Neue Komponenten kommen nach `AnvilUI`, sobald sie ein zweites Tool braucht.

## Sprache

- **Jeder Anzeigetext ist übersetzbar.** Der deutsche Text ist gleichzeitig der
  Schlüssel — es gibt keine erfundenen Schlüsselnamen.
- Literale in Views gehen an Komponenten, die `LocalizedStringKey` nehmen.
  Text aus Modellen, Katalogen und Fehlern läuft über `localized(…)`.
  Bereits übersetzte Werte werden mit `.resolved(…)` markiert.
- Nie übersetzt werden SF-Symbol-Namen, Bezeichner, Modellnamen und Pfade —
  dafür `Text(verbatim:)` bzw. `Text.raw(_:)`.
- Nach neuen Texten `./Scripts/check-translations.py` laufen lassen und
  `Resources/en.lproj/Localizable.strings` ergänzen. Details in
  `docs/LOCALIZATION.md`.

## Build

```sh
./Scripts/build-app.sh            # Debug-Bundle nach .build/debug/Anvil.app
./Scripts/build-app.sh release    # Release-Bundle
./Scripts/run.sh                  # bauen + starten
swift test                        # Unit-Tests
./Scripts/check-translations.py   # fehlende Übersetzungen
./Scripts/tool-list.py            # docs/TOOLS.md neu schreiben
```

Nach einem neuen Werkzeug gehört `./Scripts/tool-list.py` dazu — die Liste in
`docs/TOOLS.md` wird nicht von Hand gepflegt.

## Neue Tools

Ein Tool ist eine `ToolRegistration` (Metadaten + View-Builder + optionale
Settings-View). Details in `docs/ADDING_A_TOOL.md`. Für reine Prompt-Tools
reicht eine JSON-Datei in `~/Library/Application Support/Anvil/Tools/` — ohne
Neukompilieren. Aktivieren und deaktivieren lassen sich alle Tools im
Tool-Store.
