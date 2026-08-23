# Umbau: Xcode, Auslieferung, neues Erscheinungsbild

Ausgangslage: 233 Swift-Dateien, ~41.000 Zeilen, sauber geschichtet
(`AnvilKit → AnvilUI → AnvilToolbox`), Tests grün, `swift build` läuft.
Die Logik bleibt. Neu werden: das Projekt-Setup, der Auslieferungsweg und
jede sichtbare Fläche.

Gestalterische Vorlage: [`vorssaint/vorssaint-utils`](https://github.com/vorssaint/vorssaint-utils).

---

## Was aus der Vorlage übernommen wird

Vorssaint ist eine Menüleisten-App, Anvil ein Fenster mit Seitenleiste — die
Architektur wird nicht kopiert, die Bildsprache schon:

| Element | Vorlage | Umsetzung in Anvil |
| --- | --- | --- |
| Flächen | Canvas fast schwarz, Karten als `white.opacity(0.075)` darüber | vierstufiger Flächenstapel `canvas / base / card / control`, hell wie dunkel |
| Linien | Haarlinie `white.opacity(0.11)`, 0,7 pt | `AnvilColor.border`, `AnvilSize.hairline` = 0,7 |
| Radien | 10 pt Karte, 18 pt Panel, `.continuous` | Radien-Skala durchgehend auf `.continuous` |
| Abschnittstitel | VERSALIEN, 10 pt semibold, Laufweite 0,5, sekundär | `AnvilSectionHeader` |
| Zeilen | Icon im abgerundeten Quadrat, Titel + Merkmal-Pillen, Untertitel, Aktion rechts | `AnvilRow` |
| Seitenleiste | Suchfeld oben, Gruppen mit Versalien-Titeln, farbige Symbole, Auswahl als akzentgefüllte Pille | neue `SidebarView` |
| Kopfbereich | Segmentwahl statt Tabs, darunter ein Erklärsatz und eine Aktionszeile | `AnvilSegmentedControl` |
| Karten | Icon + Titel + Beschreibung + eine Aktion, im Raster | `AnvilActionCard` |

---

## Phase 0 — Xcode-Projekt und Auslieferung

**Projektform.** `Anvil.xcodeproj` mit einem echten App-Target, das die
Module als lokales Swift-Paket einbindet. Xcode 26 kann Ordner
synchronisieren (`PBXFileSystemSynchronizedRootGroup`), deshalb wird keine
Dateiliste gepflegt.

1. `Anvil.xcodeproj` anlegen (objectVersion 77, synchronisierter Ordner
   `Sources/AnvilApp`).
2. `Package.swift`: `AnvilApp` als Executable entfernen — die App gehört ab
   jetzt Xcode, die Bibliotheken dem Paket. `swift test` bleibt unberührt.
3. `Resources/Assets.xcassets` mit App-Icon; `Scripts/make-icon.swift`
   schreibt hinein statt eine `.icns` daneben zu legen.
4. `Sources/AnvilApp/Info.plist` als Target-Plist, `Resources/Anvil.entitlements`
   als Entitlements, Version aus `MARKETING_VERSION` statt aus der Plist.
5. `.swiftpm/xcode/` löschen — der geerbte Workspace steht dem Projekt im Weg.

**Auslieferung.** `Scripts/build-app.sh` baut das Bundle heute von Hand
zusammen; das entfällt.

6. `Scripts/archive.sh` — `xcodebuild archive` + `-exportArchive`.
7. `Scripts/make-dmg.sh` — DMG mit Programme-Verknüpfung statt Zip.
8. `Scripts/notarize.sh` — `notarytool submit --wait` + `stapler`, greift nur
   wenn eine Developer-ID vorliegt.
9. `.github/workflows/release.yml` neu: Der Verweis auf `Resources/Info.plist`
   zeigt ins Leere (die Datei ist verschoben) — der Workflow ist derzeit
   kaputt. Neu: Version gegen `MARKETING_VERSION` prüfen, `xcodebuild test`,
   archivieren, DMG bauen, Prüfsumme, veröffentlichen. Signierung über
   Secrets (`SIGNING_CERTIFICATE_P12`, `SIGNING_CERTIFICATE_PASSWORD`,
   `NOTARY_*`); fehlen sie, wird ad-hoc signiert und die Release-Beschreibung
   nennt den Gatekeeper-Umweg.
10. `.github/workflows/build.yml` auf `xcodebuild` umstellen, plus
    `swift test` für die Bibliotheken.
11. Ein Appcast-fähiges `latest.json` neben dem Release, damit ein späterer
    In-App-Updater nichts Neues braucht.

## Phase 1 — Gestaltungssystem (`AnvilUI/Theme`, `AnvilUI/Components`)

12. `AnvilPalette.swift` neu: Flächenstapel und Linien schemaabhängig statt
    über `NSColor`-Semantik. Statusfarben bekommen eine gedämpfte Variante
    fürs helle Schema, wie in der Vorlage.
13. `AnvilTokens.swift` entschlacken: Die Größenliste ist auf ~40 Konstanten
    angewachsen, viele davon einmal benutzt. Was ein Bauteil betrifft, wandert
    zum Bauteil.
14. Neue Bauteile: `AnvilSurface` (Karte/Panel/Steuerfläche als ein
    Modifier), `AnvilSectionHeader`, `AnvilIconBadge`, `AnvilRow`,
    `AnvilActionCard`, `AnvilSegmentedControl`, `AnvilPill`.
15. `AnvilButton`, `AnvilBanner`, `DataGrid`, `EmptyStateView`,
    `ChipPicker`, `KeyValueList` auf die neuen Flächen ziehen.

## Phase 2 — App-Hülle (`AnvilApp`)

16. `SidebarView` — Suchfeld, Gruppen mit Versalien-Titeln, farbige Symbole,
    Auswahl als gefüllte Pille, Fußzeile mit Modellstatus.
17. `StartView` → Übersichtsseite nach Vorbild des Feature-Hubs: Segmentwahl
    (Werkzeuge / Rechte), Bündelkarten oben, darunter Abschnitte aus
    `AnvilRow`.
18. `SettingsWindow` (488 Zeilen) in Seiten je Bereich zerlegen, alle auf
    `SettingsForm` mit neuen Karten.
19. `CommandPalette`, `OnboardingView`, `MenuBarContent`, `ToolWindow`.

## Phase 3 — Werkzeugflächen (`AnvilToolbox`)

20. `ToolScaffold`, `ToolHeaderBar`, `InspectorPane`, `ToolStatusBar`,
    `AnvilPane`, `WorkbenchLayout` auf die neue Sprache.
21. Die 36 Werkzeugflächen durchgehen — gruppenweise, in dieser Reihenfolge:
    Text, Data, Dev, Files, Diff, Env → Code, Git → Vision, PDF, Markdown,
    Archive → Screenshot, Speech, Prompt → Net, Time, Everyday, System, Fake.
    Jede Fläche: Optionen in den Inspektor, Ergebnis in den Content,
    Massenauswahl prüfen, keine magischen Zahlen.

> Nach Schritt 20 zeigte die Suche nach magischen Zahlen und rohen Farben in
> den Werkzeugflächen **null Treffer** — die Flächen hängen ausnahmslos an
> `ToolScaffold`, `AnvilPane` und `InspectorSection` und haben das neue
> Aussehen mitbekommen, ohne einzeln angefasst zu werden. Schritt 21 ist
> damit keine Umbauarbeit mehr, sondern eine Durchsicht Fläche für Fläche.

## Phase 4 — Abschluss

22. `./Scripts/check-translations.py` und `Resources/en.lproj/Localizable.strings`.
23. `./Scripts/tool-list.py`.
24. `swift test` + `xcodebuild test`, Probelauf des Release-Workflows
    (`dry_run: true`).
25. `README.md`, `docs/ARCHITECTURE.md`, `docs/ADDING_A_TOOL.md` nachziehen.

---

## Was nicht angefasst wird

Engines, Kataloge, Parser, Netzwerk- und Prozess-Code und die 44 Testdateien.
Das ist die Substanz und sie trägt. Geändert wird, was man sieht, und wie das
Ganze gebaut und ausgeliefert wird.

## Offen

Ohne bezahltes Entwicklerkonto bleibt die App unnotarisiert; der
Signierungspfad wird so gebaut, dass später ein Zertifikat und vier Secrets
genügen.
