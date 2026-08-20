# Mitarbeiten

Anvil ist eine native macOS-App aus sechs Targets. Wer etwas beiträgt, arbeitet
fast immer in genau einem davon — welches, entscheidet sich an einer einzigen
Frage: *Wer darf das kennen?*

## Kurz vorweg

```sh
./Scripts/run.sh                  # bauen und starten
swift test                        # Tests
./Scripts/check-translations.py   # fehlende Übersetzungen
./Scripts/tool-list.py            # docs/TOOLS.md neu schreiben
```

Die CI prüft die letzten beiden mit; wer ein Werkzeug hinzufügt, lässt
`tool-list.py` einmal laufen und legt die geänderte `docs/TOOLS.md` dazu.

Voraussetzung ist macOS 26 mit Xcode 26 bzw. einer passenden Swift-Toolchain.
`FoundationModels` und `SpeechAnalyzer` gibt es darunter nicht.

## Wo etwas hingehört

| Was du baust | Wohin |
| --- | --- |
| Tool-Modell, Registry, Storage, Kürzel-Infrastruktur | `AnvilKit` |
| Wiederverwendbare Ansicht, Token, Layout | `AnvilUI` |
| Sprachmodell-Anbieter | `AnvilAI` |
| Aufnahme, Transkription | `AnvilSpeech` |
| Ein Werkzeug, eine Werkzeug-Engine | `AnvilToolbox` |
| Fenster, Sidebar, Einstellungen, Menüleiste | `AnvilApp` |

Abhängigkeiten zeigen ausschließlich nach unten. `AnvilKit` weiß nichts von KI,
nichts von Sprache und nichts von der App-Shell — das ist keine Formalie,
sondern der Grund, warum der Kern austauschbar bleibt. Details in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Ein neues Werkzeug braucht meistens gar keinen Swift-Code: siehe
[docs/ADDING_A_TOOL.md](docs/ADDING_A_TOOL.md).

## Die vier Regeln, die wirklich gelten

**1. Kein Werkzeug baut eigenes Chrome.** Jede Tool-View sitzt in
`ToolScaffold`, Optionen kommen in die Inspector-Spalte (`InspectorSection` +
`OptionRow`), Fehler in ein `AnvilBanner` — nie in einen Alert, nie in `print`.

**2. Keine magischen Zahlen.** Abstände, Radien, Farben, Schriften und
Animationen kommen aus `AnvilSpacing`, `AnvilRadius`, `AnvilColor`, `AnvilFont`
und `AnvilMotion`. Wenn du eine Zahl brauchst, die es dort nicht gibt, ist die
Frage nicht „welche Zahl", sondern „welcher Token".

**3. Sobald ein zweites Werkzeug etwas braucht, wandert es nach `AnvilUI`.**
Einmal ist ein Detail, zweimal ist eine Komponente. Kopieren ist die eine
Sache, die hier nicht durchgeht.

**4. Jeder Anzeigetext ist übersetzbar.** Der deutsche Text *ist* der
Schlüssel — es gibt keine erfundenen Schlüsselnamen. Literale in Views gehen an
Komponenten, die `LocalizedStringKey` nehmen; Text aus Modellen, Katalogen und
Fehlern läuft über `localized(…)`, bereits übersetzte Werte über
`.resolved(…)`. Nie übersetzt werden SF-Symbol-Namen, Bezeichner, Modellnamen
und Pfade — dafür `Text(verbatim:)` bzw. `Text.raw(_:)`. Nach neuem Text
`./Scripts/check-translations.py` laufen lassen und
`Resources/en.lproj/Localizable.strings` ergänzen; mehr in
[docs/LOCALIZATION.md](docs/LOCALIZATION.md).

## Tests

Getestet wird, was eine richtige und eine falsche Antwort hat: Parser,
Formatierer, Korrektoren, Argumentlisten. Views werden nicht getestet. Wenn
etwas schwer zu testen ist, weil es in einer View steckt, ist meistens die
Logik am falschen Ort — nicht der Test zu aufwendig.

`swift test` muss durchlaufen, bevor du etwas schickst.

## Commits

- Imperativ, auf Deutsch, eine Zeile Betreff.
- Die Commit-Nachricht beschreibt **die Änderung**, nicht den Weg dorthin.
- Keine Werkzeug-Signaturen, keine Co-Autoren-Zeilen, keine Footer.

Beispiele aus der Historie:

```
Gieß den Aufbau der Werkzeuge in eine Komponente
Lege ColorValue in den Kern
Merke dir das Fenster und lass den Agenten mitschreiben
```

## CI

Jeder Push baut auf einem `macos-26`-Runner und lässt die Tests laufen; ein
zweiter Job prüft die Übersetzungen. Rot heißt rot — ein Pull Request mit rotem
Build ist nicht fertig, egal wie klein die Änderung aussieht.
