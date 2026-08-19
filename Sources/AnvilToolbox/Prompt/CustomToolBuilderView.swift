import AnvilKit
import AnvilUI
import AppKit
import SwiftUI

/// Ein Werkzeug, das Werkzeuge anlegt.
public struct CustomToolBuilderView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var draft = CustomToolDraft()
    @State private var note: String?
    @State private var error: AnvilError?
    @State private var orientation: WorkbenchOrientation = .horizontal

    public init(context: ToolContext, metadata: ToolMetadata) {
        self.context = context
        self.metadata = metadata
    }

    private var library: (any ToolLibraryReloading)? { context.resolve() }

    /// Die Kennungen, die es schon gibt — die eingebauten wie die eigenen.
    private var taken: Set<String> {
        var identifiers = Set(context.registry.allTools.map(\.id.rawValue))
        if isEditingExisting { identifiers.remove(draft.identifier) }
        return identifiers
    }

    /// Ob gerade eine Datei nachgebessert wird, die es schon gibt.
    @State private var isEditingExisting = false

    private var problems: [CustomToolDraft.Problem] { draft.problems(existing: taken) }

    public var body: some View {
        ToolScaffold(metadata: metadata) {
            content
        } inspector: {
            inspector
        } actions: {
            WorkbenchOrientationPicker(orientation: $orientation)

            AnvilButton("Ordner öffnen", systemImage: "folder") {
                AppPaths.bootstrap()
                NSWorkspace.shared.open(library?.userToolsDirectory ?? AppPaths.customTools)
            }

            AnvilButton("Werkzeug anlegen", systemImage: "plus.circle", role: .primary) {
                save()
            }
            .disabled(!draft.isReady(existing: taken))
        }
        .anvilErrorBanner($error)
    }

    // MARK: - Anlegen

    private func save() {
        note = nil
        do {
            let directory = library?.userToolsDirectory ?? AppPaths.customTools
            let url = try draft.write(to: directory)
            let count = library?.reloadUserTools() ?? 0
            isEditingExisting = true
            note = localized("Angelegt als \(url.lastPathComponent). Es steht jetzt unter „Eigene Tools\" — \(count) eigene insgesamt.")
        } catch {
            self.error = AnvilError.wrapping(error)
        }
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
            instructionPane
        } secondary: {
            previewPane
        } status: {
            statusBar
        }
    }

    private var instructionPane: some View {
        AnvilPane("Anweisung", systemImage: "text.bubble") {
            AnvilTextEditor(
                text: $draft.instructions,
                placeholder: "Du bist ein Werkzeug in Anvil. Antworte ausschließlich mit dem Ergebnis, ohne Einleitung und ohne Rückfragen.\n\nAufgabe: …"
            )
        } accessory: {
            Button { draft.instructions = context.pasteboard.string() ?? draft.instructions } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp("Einfügen")
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        AnvilPane("Die Datei", systemImage: "curlybraces", tone: .neutral) {
            AnvilTextView(draft.json(), isMonospaced: true)
        } accessory: {
            CopyButton(text: draft.json())
        }

        if let note {
            AnvilBanner(title: .resolved(note), tone: .success, onDismiss: { self.note = nil })
                .padding(AnvilSpacing.md)
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric(draft.identifier, label: "Kennung", systemImage: "number")
            if draft.hasOption {
                StatusMetric(
                    "\(draft.choices.count)",
                    label: "Möglichkeiten",
                    systemImage: "list.bullet"
                )
            }
        } trailing: {
            if draft.isReady(existing: taken) {
                StatusPill("bereit", systemImage: "checkmark", tone: .success)
            } else {
                StatusPill("noch nicht", systemImage: "hand.raised", tone: .neutral)
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Das Werkzeug",
            systemImage: "wrench.and.screwdriver",
            footnote: "Die Kennung entsteht aus dem Titel. Sie steht in Favoriten und im Fensterzustand — ändert sich der Titel, ist es ein neues Werkzeug."
        ) {
            OptionRow("Titel") {
                AnvilTextField(text: $draft.title, placeholder: "Änderungstext schreiben")
            }
            OptionRow("Untertitel") {
                AnvilTextField(text: $draft.subtitle, placeholder: "Aus einem Diff eine Notiz")
            }
            OptionRow("Symbol") {
                AnvilTextField(text: $draft.systemImage, placeholder: "wand.and.stars", isMonospaced: true)
            }
            OptionRow("Schlagwörter") {
                AnvilTextField(text: $draft.keywords, placeholder: "diff, notiz, release")
            }
        }

        InspectorSection(
            "Eingabe",
            systemImage: "text.cursor",
            footnote: "Der Text, den jemand hineinschreibt, wird für {{input}} eingesetzt."
        ) {
            OptionRow("Platzhalter") {
                AnvilTextField(text: $draft.inputPlaceholder, placeholder: "Diff einfügen …")
            }
        }

        InspectorSection(
            "Eine Wahl",
            systemImage: "slider.horizontal.3",
            footnote: "Leer lassen, wenn das Werkzeug keine braucht. Sonst muss der Platzhalter in der Anweisung vorkommen — nur dort tut die Wahl etwas."
        ) {
            OptionRow("Beschriftung") {
                AnvilTextField(text: $draft.optionLabel, placeholder: "Ausführlichkeit")
            }
            OptionRow("Möglichkeiten") {
                AnvilTextField(text: $draft.optionChoices, placeholder: "knapp, normal, ausführlich")
            }
            if draft.hasOption {
                AnvilButton("Platzhalter einsetzen", systemImage: "text.insert") {
                    draft.instructions += draft.instructions.isEmpty
                        ? draft.optionPlaceholder
                        : " " + draft.optionPlaceholder
                }
            }
        }

        InspectorSection(
            "Temperatur",
            systemImage: "thermometer.medium",
            footnote: "Niedrig heißt gleichmäßig, hoch heißt einfallsreich. Für Werkzeuge ist niedrig fast immer richtig."
        ) {
            AnvilSlider(value: $draft.temperature, in: 0...1, step: 0.1)
        }

        if !problems.isEmpty {
            InspectorSection("Was noch fehlt", systemImage: "exclamationmark.triangle") {
                KeyValueList(problems.map { problem in
                    KeyValueList.Item(
                        problem.title,
                        problem.isBlocking ? localized("nötig") : localized("Hinweis"),
                        tone: problem.isBlocking ? .warning : .neutral
                    )
                })
            }
        }
    }
}
