# Architektur

Anvil ist in sechs Targets geschnitten. Abhängigkeiten zeigen ausschließlich
nach unten — jede Schicht kennt nur die unter ihr.

```
AnvilApp          Fenster, Sidebar, Command-Palette, Einstellungen, Menüleiste
   │
AnvilToolbox      die Tools selbst + die generischen Tool-Engines
   │
   ├── AnvilAI    Sprachmodelle: Foundation Models, OpenAI-kompatibel, Anthropic
   ├── AnvilSpeech Aufnahme + Transkription (SpeechAnalyzer)
   │
AnvilUI           Design-System: Tokens, Layouts, Komponenten
   │
AnvilKit          Tool-Modell, Registry, Kontext, Storage, Utilities
```

`AnvilKit` weiß nichts von KI, nichts von Sprache und nichts von der App-Shell.
Das ist Absicht: der Kern soll austauschbar bleiben.

## AnvilKit — der Erweiterbarkeits-Kern

| Typ | Aufgabe |
| --- | --- |
| `ToolIdentifier` | stabile ID, landet in Favoriten, Verlauf, Fensterzustand |
| `ToolMetadata` | alles, was die Shell über ein Tool weiß, ohne es zu bauen |
| `ToolCategory` | Sidebar-Abschnitt — ein Struct, damit neue Kategorien möglich sind |
| `ToolRegistration` | Metadaten + View-Builder + optionale Settings-View |
| `ToolBundle` | Gruppe von Tools; die Einheit der Erweiterung |
| `ToolOrigin` | woher ein Tool kommt (eingebaut, System, Nutzerdatei) |
| `ToolRegistry` | kennt alle Tools, liefert die aktiven, sucht, sortiert |
| `ToolActivationStore` | welche Tools und Sammlungen eingeschaltet sind |
| `ToolContext` | Dependency-Container, den jedes Tool bekommt |
| `SettingsStore` | typisierte, beobachtbare Einstellungen über `UserDefaults` |
| `KeychainStore` | API-Schlüssel — niemals in den Einstellungen |
| `HistoryStore` | Durchläufe pro Tool, als JSON auf der Platte |
| `DraftStore` | was zuletzt im Tool stand — nur, wenn es unverfänglich ist |
| `Sensitivity` | erkennt Schlüssel, Tokens und Zugangsdaten in Text |
| `GlobalShortcut` | Tastenkombination für systemweite Kürzel |
| `HotKeyCenter` | Registrierung über Carbon — ohne Bedienungshilfen-Recht |
| `PasteService` | ⌘V in die vorherige App; das einzige Stück mit Accessibility |
| `ShortcutRegistry` | alle Kürzel der App: ändern, abschalten, app-weit oder global |
| `ProcessRunner` | externe Befehle mit Zeitlimit, auch als Strom |
| `ColorValue` | Farben parsen, umrechnen, Kontrast bewerten |
| `TextDiff`, `FuzzyMatch` | Vergleich und Ähnlichkeit, für Textvergleich und Vokabular |
| `NSImage.writePNG(to:)` | Bilder als PNG sichern — eine Fassung für alle Tools |

### Warum Metadaten und View getrennt sind

Die Registry hält hunderte `ToolMetadata` — klein, `Sendable`, durchsuchbar.
Die View entsteht erst, wenn ein Tool geöffnet wird. Sidebar, Suche und
Tool-Store fassen deshalb nie Tool-Code an.

### Der Kontext als Naht

`ToolContext` ist ein typbasierter Service-Container. `AnvilKit` legt Settings,
Verlauf und Zwischenablage hinein; höhere Schichten registrieren ihre Dienste
und legen eine kleine typisierte Erweiterung dazu:

```swift
extension ToolContext {
    public var ai: AIRouter { require(AIRouter.self) }
}
```

Ein Tool schreibt `context.ai` und weiß nicht, woher der Router kommt. In Tests
und Previews wird stattdessen ein Stub registriert.

## AnvilUI — das Design-System

Regel: **kein Tool baut eigenes Chrome.** Jede Tool-View sitzt in
`ToolScaffold` und bekommt Kopfzeile, Inhaltsbereich, Inspector-Spalte und
Header-Aktionen. Abstände, Radien, Farben, Schriften und Animationen kommen aus
`AnvilSpacing`, `AnvilRadius`, `AnvilColor`, `AnvilFont`, `AnvilMotion`.

Wichtigste Bausteine: `ToolScaffold`, `ToolWorkbench` (zwei Bereiche plus
Statusleiste — die Form, die praktisch jedes Tool hat), darunter
`WorkbenchLayout` für die verschiebbare Teilung selbst, `InspectorPane` +
`InspectorSection` + `OptionRow`, `AnvilPane`, `ToolStatusBar`,
`SettingsPage`/`SettingsGroup`/`SettingsRow`, dazu `AnvilButton`,
`AnvilBanner`, `ChipPicker`, `StatusPill`, `EmptyStateView`, `DiffTextView`,
`LevelMeter`.

Ein Tool greift auf `WorkbenchLayout` nur zu, wenn es etwas anderes als „zwei
Bereiche, Statusleiste" braucht — bisher tut das keines. Sobald ein zweites
Tool etwas Eigenes zweimal baut, gehört es hierher: das ist die Regel, an der
sich entscheidet, was `AnvilUI` kennt.

`.anvilFileDrop(_:error:perform:)` nimmt gezogene Dateien an: Rahmen während
des Ziehens, Textdatei oder Bild als Ergebnis, und für alles andere eine
Fehlermeldung statt Schweigen. Das Lesen selbst macht `TextFile` im Kern —
Kodierung raten, Byte Order Marks auswerten, Binärdateien erkennen.

## AnvilAI — Modelle

`AIProvider` ist die Abstraktion: Verfügbarkeit, einmalige Antwort, Streaming.
Streaming liefert immer den **kumulierten** Text, nicht Deltas — so kann eine
View direkt daran hängen.

Implementierungen: `FoundationModelsProvider` (on-device),
`CLIAgentProvider` (Claude Code, Codex, Gemini CLI — über die vorhandene
Anmeldung, ohne API-Schlüssel), `OpenAICompatibleProvider` (OpenAI, Ollama,
LM Studio, OpenRouter, Gateways), `AnthropicProvider`.

`CLIAgentLocator` findet die Befehle. Eine GUI-App erbt den `PATH` von
`launchd`, und der kennt keines der Verzeichnisse, in die npm, Homebrew oder
pipx installieren — deshalb erst die bekannten Orte, dann einmal die
Login-Shell fragen, und das Ergebnis merken.

`AIRouter` wählt aus. Die Richtlinie (`AIPolicy`) ist eine einzige Einstellung
statt eines Versprechens, das über zwanzig Tools verteilt ist:

- `onDeviceOnly` — nichts verlässt den Mac, notfalls fällt das Tool aus
- `preferOnDevice` — Apple-Modell zuerst, extern nur als Rückfallebene
- `preferRemote` — extern zuerst

Der Router wechselt außerdem selbstständig zum externen Anbieter, wenn die
Eingabe größer ist als das On-Device-Kontextfenster.

## AnvilSpeech — Sprache

`AudioRecorder` nimmt auf und reicht Puffer weiter, `BufferConverter` bringt sie
in das Format des Analyzers, `LiveTranscriptionSession` betreibt
`SpeechAnalyzer` + `SpeechTranscriber`, `TranscriptionModelCatalog` kümmert sich
um Sprachpakete und Reservierungen, `AudioFileTranscriber` macht dasselbe für
fertige Dateien. `DictationSession` fasst Aufnahme und Erkennung zu der Einheit
zusammen, die Tools tatsächlich bedienen.

`QuickDictationController` (in `AnvilToolbox`) setzt darauf das Diktat von
überall: globales Kürzel über `HotKeyCenter`, eine kleine Bubble über allen
Apps, deterministische Bereinigung plus optionaler Modell-Durchlauf, danach
Zwischenablage und — sofern der Cursor in einem Textfeld stand — ⌘V in die App,
die vorher vorne war.

Die Bubble nimmt **nie** den Tastaturfokus. Das ist die eine Entscheidung, an
der das Einfügen hängt: ein Fenster, das Key wird, zieht den Fokus aus dem
Zieltextfeld, und in manchen Apps geht dabei die Auswahl verloren. Escape wird
deshalb nicht über das Fenster gelöst, sondern während der Aufnahme kurzzeitig
als globales Kürzel belegt. Ob überhaupt eingefügt wird, entscheidet
`PasteService.focusedElementIsEditable()` — abgefragt beim Tastendruck, bevor
irgendetwas von Anvil sichtbar ist.

Zwei Fallstricke sind hier bewusst gelöst:

- Der Audio-Tap läuft nicht auf dem Main-Actor. Alles, was `feed(_:)` anfasst,
  ist deshalb `nonisolated` — ein Actor-Hop käme zu spät, der Puffer wäre
  schon wiederverwendet.
- `finalizeAndFinishThroughEndOfInput()` muss abgewartet werden, sonst fehlen
  die letzten Wörter.

## AnvilToolbox — die Tools

Drei Wege, ein Tool zu bauen:

1. **`TextTool`** — deterministisch, reine Funktion `String -> String`. Läuft
   live bei jedem Tastendruck. Alle Konverter (JSON, Base64, Hashes, JWT …)
   sind Einträge in `TextToolCatalog`.
2. **`AIPromptTool`** — ein Prompt plus Optionen, `Codable`. Die eingebauten
   KI-Tools und die selbstgeschriebenen aus dem Tools-Ordner sind derselbe Typ.
3. **Eigene View** — für alles, was mehr braucht, etwa das Speech Studio.

## Datenablage

```
~/Library/Application Support/Anvil/
├── Tools/         eigene Prompt-Tools (JSON)
├── Recordings/    Diktate
├── History/       Verlauf pro Tool
└── Exports/       gesicherte Ergebnisse
```

API-Schlüssel liegen im Schlüsselbund, nicht in `UserDefaults`.
