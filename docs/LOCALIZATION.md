# Übersetzungen

## Grundsatz: der deutsche Text ist der Schlüssel

Anvil wird auf Deutsch entwickelt, und der deutsche Quelltext ist gleichzeitig
der Nachschlage-Schlüssel:

```swift
Text("Aufnehmen")                      // Schlüssel: "Aufnehmen"
localized("Es gibt noch keinen Text.") // Schlüssel: "Es gibt noch keinen Text."
```

Das hat drei Folgen, die den Alltag deutlich angenehmer machen:

- Es gibt **keine erfundenen Schlüssel** wie `speech.record.button`, die man mit
  dem Text synchron halten müsste.
- Eine **fehlende Übersetzung fällt auf korrektes Deutsch zurück** — nie auf
  einen sichtbaren Schlüsselnamen.
- Eine **neue Sprache ist ein Ordner**: `Resources/<code>.lproj/Localizable.strings`
  anlegen, Werte übersetzen, in der `Info.plist` unter `CFBundleLocalizations`
  eintragen. Fertig.

Deutsch hat deshalb bewusst **kein** eigenes `.lproj` — seine Strings *sind* die
Schlüssel.

## Wo die Dateien liegen

```
Resources/
├── Info.plist                    CFBundleDevelopmentRegion = de, CFBundleLocalizations
└── en.lproj/Localizable.strings  englische Übersetzungen
```

Das App-Target in `Anvil.xcodeproj` kopiert jedes `.lproj` nach
`Anvil.app/Contents/Resources/`. Alles schlägt gegen `Bundle.main` nach — also
das App-Bundle. Bibliotheks-Targets brauchen deshalb **kein** `bundle: .module`
und kein `Bundle.module`.
> `Localization.hasLoadedTranslations` sagt, ob welche gefunden wurden.

## Welche Schreibweise wann

| Situation | Schreibweise |
| --- | --- |
| Literal in einer View | `Text("Aufnehmen")` oder eine Anvil-Komponente — die nehmen `LocalizedStringKey` |
| Text aus Modell, Katalog oder Fehler | `localized("…")` |
| Anzeigetext, der als Datum zur Laufzeit ankommt | `localized(runtime: value)` |
| Bereits übersetzter String an eine Komponente | `.resolved(value)` |
| Darf **nie** übersetzt werden | `Text(verbatim:)` bzw. `Text.raw(_:)` |

`.resolved(_:)` ist der Marker für „ist schon übersetzt". Technisch ist es ein
zweiter Nachschlagevorgang, der ins Leere läuft und den Wert durchreicht — der
Sinn ist, dass man beim Lesen sofort sieht, welcher String schon fertig ist.

### Was automatisch übersetzt wird

`ToolMetadata`, `ToolCategory`, `ToolOrigin` und `TextToolMode` übersetzen ihre
Anzeigetexte **im Initializer**. Ein Tool-Katalog schreibt also einfach:

```swift
TextTool(id: "text.json", title: "JSON", subtitle: "Formatieren, verkleinern, prüfen", …)
```

… und Sidebar, Suche, Tool-Store und Fenstertitel bekommen alle denselben
übersetzten String. Selbstgeschriebene Tools aus dem Tools-Ordner laufen durch
denselben Weg: Titel ohne Eintrag im Katalog bleiben einfach, wie sie sind.

### Werte in Sätzen

Interpolation gehört in den Schlüssel, nicht drumherum:

```swift
localized("\(count) Wörter")     // Schlüssel: "%lld Wörter"
localized("Kopiert: \(name)")    // Schlüssel: "Kopiert: %@"
```

Zahlen werden zu `%lld`, Strings zu `%@`. Im `.strings` muss der Schlüssel genau
diese Form haben, sonst greift die Übersetzung nicht.

## Was absichtlich Deutsch bleibt

**Die Prompt-Texte der KI-Tools** (`AIPromptCatalog`, `RefinementStyle`) sind
nicht übersetzt. Sie richten sich an das Modell, nicht an Menschen, und jedes
brauchbare Modell versteht sie. Wichtiger ist die Regel *in* den Prompts:
„Antworte in der Sprache der Eingabe" — englischer Text bekommt also englische
Antworten, unabhängig von der Sprache des Prompts.

Ebenfalls unübersetzt: SF-Symbol-Namen, Modell- und Anbieternamen, Formatnamen
wie `camelCase`, Beispielwerte und Dateipfade.

## Lücken finden

```sh
./Scripts/check-translations.py           # meldet, was in en.lproj fehlt
./Scripts/check-translations.py --list    # alle gefundenen Anzeigetexte
```

Das Skript liest die Aufrufstellen im Quelltext, bildet daraus die Schlüssel
(inklusive `%lld`/`%@`) und vergleicht sie mit der `.strings`-Datei. Bezeichner
und Beispielwerte stehen in der `SKIP`-Liste im Skript.

## Eine Sprache ergänzen

1. `Resources/en.lproj/Localizable.strings` nach `Resources/fr.lproj/` kopieren.
2. Werte übersetzen, Schlüssel unverändert lassen.
3. In `Resources/Info.plist` unter `CFBundleLocalizations` `fr` ergänzen.
4. In Xcode die neue Datei zur Variantengruppe `Localizable.strings` legen und
   `fr` unter „Localizations" im Projekt eintragen — ohne das landet der Ordner
   nicht im Bundle.
5. `./Scripts/check-translations.py --language fr`
