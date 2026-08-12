# Ein neues Tool bauen

Vier Wege, vom billigsten zum aufwendigsten. Nimm den ersten, der reicht.

## 1. Prompt-Tool ohne Neukompilieren

Eine JSON-Datei in `~/Library/Application Support/Anvil/Tools/`. Anvil legt beim
ersten Start eine `beispiel-tool.json` als Vorlage an.

**Der kürzeste Weg dahin führt durch die App:** Das Werkzeug „Eigenes Werkzeug"
fragt nach Titel, Anweisung und einer Wahlmöglichkeit, zeigt die Datei daneben,
während sie entsteht, und legt sie an. Es sagt außerdem vorher, was fehlt — eine
Kennung, die es schon gibt, etwa, oder eine Wahl, die in der Anweisung gar nicht
vorkommt. Wer die Datei einmal gesehen hat, schreibt die nächste von Hand; dafür
steht sie hier.

```json
{
  "id": "user.protokoll",
  "title": "Protokoll",
  "subtitle": "Aus Notizen ein Besprechungsprotokoll",
  "systemImage": "doc.text",
  "categoryID": "everyday",
  "keywords": ["protokoll", "meeting", "notizen"],
  "instructions": "Du machst aus Notizen ein Protokoll. Antworte ausschließlich mit dem Ergebnis.\n\nGliederung: Thema, Beschlüsse, offene Punkte.\nLänge: {{option:length}}.",
  "promptTemplate": "{{input}}",
  "options": [
    {
      "id": "length",
      "label": "Länge",
      "kind": "choice",
      "choices": ["knapp", "ausführlich"],
      "defaultValue": "knapp"
    }
  ],
  "temperature": 0.3,
  "inputPlaceholder": "Notizen aus der Besprechung …",
  "isMonospacedInput": false,
  "inputSource": "text"
}
```

Platzhalter: `{{input}}` für den Eingabebereich, `{{option:id}}` für jede
Option — beides funktioniert in `promptTemplate` **und** in `instructions`.

`categoryID`: `speech`, `coding`, `text`, `everyday`, `custom`.
`inputSource`: `text` oder `gitDiff` (liest `git diff --staged` aus einem
gewählten Repository).

Danach im Tool-Store auf „Neu laden" (oder ⌘⌥R). Eine kaputte Datei nimmt die
anderen nicht mit — der Fehler steht im Store.

## 2. Eingebautes Prompt-Tool

Einen Eintrag in `AIPromptCatalog.coding` oder `.everyday` ergänzen. Gleicher
Typ wie oben, nur in Swift geschrieben und mitkompiliert.

## 3. Deterministisches Tool

Für alles, was ohne Modell auskommt: einen `TextTool` in `TextToolCatalog`
ergänzen und in `TextToolCatalog.all` aufnehmen.

```swift
static var reverse: TextTool {
    TextTool(
        id: "text.reverse",
        title: "Umdrehen",
        subtitle: "Text rückwärts",
        systemImage: "arrow.left.arrow.right",
        keywords: ["reverse", "umdrehen"],
        modes: [
            TextToolMode(id: "chars", title: "Zeichen") { String($0.reversed()) },
            TextToolMode(id: "words", title: "Wörter") {
                $0.split(separator: " ").reversed().joined(separator: " ")
            }
        ]
    )
}
```

Jeder Modus ist eine reine Funktion. Sie läuft live bei jedem Tastendruck, also
darf sie nicht blockieren. Ungültige Eingaben wirft man als
`AnvilError.invalidInput(_:)` — die Meldung erscheint im Ergebnisbereich.

### Zwei Schalter, die man kennen sollte

**`handlesSecrets: true`** — setzen, sobald die Eingabe ihrem Wesen nach ein
Geheimnis sein *kann*: ein Token, ein Passwort, etwas Kodiertes, in dem beides
stecken darf. Dann merkt sich Anvil dort nie etwas. Die Inhaltsprüfung
(`Sensitivity`) greift zusätzlich, aber sie erkennt keinen hex-kodierten
Schlüssel — deshalb gibt es diesen Schalter überhaupt.

**`runOnFile:` am Modus** — dieselbe Variante, aber über eine Datei statt über
getippten Text. Wer sie setzt, macht sein Werkzeug zum Ziel für gezogene
Dateien; wer sie weglässt, nimmt keine an. Gebraucht wird sie, wo eine Datei
etwas anderes ist als ihr Text:

```swift
TextToolMode(
    id: "sha256",
    title: "SHA-256",
    runOnFile: { try FileDigest.hex(SHA256.self, of: $0) }
) { input in
    hexString(SHA256.hash(data: Data(input.utf8)))
}
```

Gerechnet wird abseits des Hauptthreads; die Datei wird blockweise gelesen,
damit ein Betriebssystem-Image nicht im Arbeitsspeicher landet.

## 4. Tool mit eigener Oberfläche

Für alles, was mehr als Text rein / Text raus ist.

```swift
public enum MeinToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.meins"
    public static let displayName = "Meine Werkzeuge"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        let metadata = ToolMetadata(
            id: "meins.tool",
            title: "Mein Tool",
            subtitle: "Was es tut",
            systemImage: "hammer",
            category: .coding,
            keywords: ["stichwort"],
            requirements: [.languageModel]
        )

        return [
            ToolRegistration(metadata: metadata) { context in
                MeinToolView(context: context, metadata: metadata)
            } settings: { context in
                MeinToolSettingsView(context: context)   // optional
            }
        ]
    }
}
```

Dann in `AppEnvironment.registerBundles()` eintragen. Mehr ist nicht nötig:
Sidebar, Suche, Command-Palette, Tool-Store und Einstellungen greifen alle auf
die Registry zu.

### Die View

```swift
struct MeinToolView: View {
    let context: ToolContext
    let metadata: ToolMetadata

    @State private var input = ""
    @State private var orientation: WorkbenchOrientation = .horizontal

    var body: some View {
        ToolScaffold(metadata: metadata) {
            ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
                AnvilPane("Eingabe", systemImage: "square.and.pencil") {
                    AnvilTextEditor(text: $input, placeholder: "…")
                }
            } secondary: {
                AnvilPane("Ergebnis", systemImage: "sparkles") {
                    EmptyStateView(title: "Noch nichts", systemImage: "sparkles")
                }
            } status: {
                ToolStatusBar {
                    StatusMetric("\(input.count)", label: "Zeichen", systemImage: "textformat")
                }
            }
        } inspector: {
            InspectorSection("Optionen", systemImage: "slider.horizontal.3") {
                OptionRow("Irgendwas") { Toggle("", isOn: .constant(true)) }
            }
        } actions: {
            AnvilButton("Ausführen", systemImage: "play.fill", role: .primary) { }
            WorkbenchOrientationPicker(orientation: $orientation)
        }
    }
}
```

## Regeln

- **Kein eigenes Chrome.** Kopfzeile, Ränder und Optionsspalte kommen vom
  Scaffold.
- **Keine magischen Zahlen.** Abstände und Farben aus `AnvilSpacing`,
  `AnvilColor`, `AnvilFont`, `AnvilRadius`, `AnvilMotion`.
- **Optionen in den Inspector**, nicht in den Inhaltsbereich.
- **Fehler über `AnvilBanner`** bzw. `.anvilErrorBanner(...)`, nie über Alerts.
- **Modelle über `context.ai`**, nie einen Provider direkt bauen — sonst gilt
  die Datenschutz-Richtlinie des Nutzers für dieses eine Tool nicht.
- **Lange Eingaben chunken** über `TextChunker.split(_:budget:)` mit dem Budget
  aus `router.inputBudget()`.
- **Neue Komponente?** Sobald ein zweites Tool sie braucht, gehört sie nach
  `AnvilUI`.
- **Anzeigetexte sind übersetzbar.** Literale in der View gehen an Komponenten,
  die `LocalizedStringKey` nehmen; Text aus dem Katalog läuft über `localized(…)`
  oder wird — bei `ToolMetadata` und `TextToolMode` — automatisch im Initializer
  übersetzt. Danach `./Scripts/check-translations.py`. Siehe
  `docs/LOCALIZATION.md`.

## Requirements deklarieren

`ToolMetadata.requirements` sagt der Shell, warum ein Tool gerade nicht kann:
`.languageModel`, `.onDeviceLanguageModel`, `.microphone`, `.speechRecognition`,
`.network`, `.git`. Der Tool-Store zeigt sie als Merkmale an.

## Tastenkürzel

Ein Tool meldet **kein** Tastenkürzel selbst an. Es beschreibt eine
`ShortcutAction`, und `ShortcutRegistry` entscheidet, worauf gehört wird:

```swift
ShortcutAction(
    id: "meintool.los",
    title: "Loslegen",
    subtitle: "Was das Kürzel auslöst",
    systemImage: "play",
    toolID: MeinToolBundle.toolID,     // gruppiert es in den Einstellungen
    defaultShortcut: GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_L),
        carbonModifiers: UInt32(optionKey | cmdKey),
        keyLabel: "L"
    ),
    defaultScope: .global               // .off, .app oder .global
) { controller.los() }
```

Drei Punkte, die daran hängen:

- **Registriert wird beim Start**, in `AppEnvironment`, nicht in der View. Ein
  globales Kürzel muss funktionieren, während das Tool zu ist — was es auslöst,
  muss also länger leben als jede View. Deshalb sitzt die Logik in einem
  Controller, den die App besitzt und über `ToolContext` bereitstellt.
- **`.app` heißt Menüeintrag.** Anders kennt macOS kein App-Kürzel; die App-Shell
  baut aus jeder Aktion mit dieser Reichweite automatisch einen Eintrag im
  Menü „Aktionen". Tasten der Funktionsreihe können nur `.global` sein —
  `KeyEquivalent` kann F5 nicht ausdrücken.
- **Kollisionen** erkennt die Registry selbst, auch die zwischen einem App- und
  einem globalen Kürzel: das globale schluckt die Taste, bevor das Menü sie
  sieht.

Der Nutzer kann jedes Kürzel unter Einstellungen › Tastenkürzel ändern,
abschalten oder in seiner Reichweite umstellen. Die Vorgabe ist eine Vorgabe,
keine Festlegung.
