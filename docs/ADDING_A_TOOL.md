# Ein neues Tool bauen

Vier Wege, vom billigsten zum aufwendigsten. Nimm den ersten, der reicht.

## 1. Prompt-Tool ohne Neukompilieren

Eine JSON-Datei in `~/Library/Application Support/Anvil/Tools/`. Anvil legt beim
ersten Start eine `beispiel-tool.json` als Vorlage an.

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
            WorkbenchLayout(orientation: $orientation, storageKey: metadata.id.rawValue) {
                AnvilPane("Eingabe", systemImage: "square.and.pencil") {
                    AnvilTextEditor(text: $input, placeholder: "…")
                }
            } secondary: {
                AnvilPane("Ergebnis", systemImage: "sparkles") {
                    EmptyStateView(title: "Noch nichts", systemImage: "sparkles")
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

## Requirements deklarieren

`ToolMetadata.requirements` sagt der Shell, warum ein Tool gerade nicht kann:
`.languageModel`, `.onDeviceLanguageModel`, `.microphone`, `.speechRecognition`,
`.network`, `.git`. Der Tool-Store zeigt sie als Merkmale an.
