import AnvilKit
import AnvilUI
import SwiftUI
import UniformTypeIdentifiers

/// Aus einer Beispielantwort Typen machen.
public struct ModelToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var input = ""
    @State private var rootName = "Root"
    @State private var language = ModelGenerator.Language.swift
    @State private var error: AnvilError?
    @State private var orientation: WorkbenchOrientation = .horizontal

    public init(context: ToolContext, metadata: ToolMetadata) {
        self.context = context
        self.metadata = metadata
    }

    /// Was aus der Eingabe wurde — oder warum nichts daraus wurde.
    private var parsed: Result<StructuredValue, AnvilError>? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        do {
            return .success(try StructuredValue.json(parsing: text))
        } catch {
            return .failure(AnvilError.wrapping(error))
        }
    }

    private var model: ModelGenerator {
        guard case let .success(value) = parsed else { return .empty }
        return ModelGenerator.infer(value, rootName: rootName.isEmpty ? "Root" : rootName)
    }

    private var output: String { model.text(language) }

    public var body: some View {
        ToolScaffold(metadata: metadata) {
            content
        } inspector: {
            inspector
        } actions: {
            WorkbenchOrientationPicker(orientation: $orientation)

            if !output.isEmpty {
                AnvilButton("Sichern", systemImage: "square.and.arrow.down", role: .primary) {
                    save()
                }
            }
        }
        .anvilErrorBanner($error)
        .anvilFileDrop(.text, error: $error) { dropped in
            guard case let .text(text, url) = dropped else { return }
            input = text
            if let url {
                rootName = ModelGenerator.typeName(url.deletingPathExtension().lastPathComponent)
            }
        }
    }

    private func save() {
        do {
            try SavePanel.write(
                output,
                suggestedName: "\(rootName).\(language.fileExtension)",
                type: .sourceCode
            )
        } catch {
            self.error = AnvilError.wrapping(error)
        }
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
            inputPane
        } secondary: {
            outputPane
        } status: {
            statusBar
        }
    }

    private var inputPane: some View {
        AnvilPane("Beispiel", systemImage: "curlybraces") {
            AnvilTextEditor(
                text: $input,
                placeholder: "JSON hier einfügen — eine Antwort, ein Ausschnitt, eine ganze Datei.",
                isMonospaced: true
            )
        } accessory: {
            if !input.isEmpty {
                ClearButton(help: "Eingabe leeren") { input = "" }
            }
        }
    }

    @ViewBuilder
    private var outputPane: some View {
        AnvilPane("Typen", systemImage: language.systemImage, tone: .neutral) {
            if case let .failure(failure) = parsed {
                EmptyStateView(
                    title: "Kein gültiges JSON",
                    message: .resolved(failure.message),
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            } else if output.isEmpty {
                EmptyStateView(
                    title: "Noch nichts abzuleiten",
                    message: "Links ein Beispiel einfügen. Aus einem Objekt wird ein Typ, aus einer Liste von Objekten einer mit optionalen Feldern.",
                    systemImage: "text.append"
                )
            } else {
                AnvilTextView(output, isMonospaced: true)
            }
        } accessory: {
            if !output.isEmpty {
                CopyButton(text: output)
                HandoffMenu(context: context, from: metadata.id, text: output)
            }
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(model.types.count)", label: "Typen", systemImage: "cube")
            StatusMetric(
                "\(model.fieldCount)",
                label: "Felder",
                systemImage: "list.bullet",
                tone: .accent
            )
            StatusMetric(
                "\(model.optionalCount)",
                label: "optional",
                systemImage: "questionmark.circle"
            )
        } trailing: {
            StatusPill(.resolved(language.title), systemImage: language.systemImage, tone: .neutral)
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Sprache",
            systemImage: "chevron.left.forwardslash.chevron.right"
        ) {
            ChipPicker(
                selection: $language,
                options: ModelGenerator.Language.allCases,
                title: { $0.title },
                systemImage: { $0.systemImage }
            )
        }

        InspectorSection(
            "Name der Wurzel",
            systemImage: "textformat",
            footnote: "Die inneren Typen heißen nach ihrem Feld — `adressen` wird zu `Adresse`. Wo die Faustregel danebenliegt, ist es ein Umbenennen in einem Zug."
        ) {
            AnvilTextField(text: $rootName, placeholder: "Root", isMonospaced: true)
        }

        if !model.isEmpty {
            InspectorSection(
                "Was abgeleitet wurde",
                systemImage: "list.bullet.rectangle",
                footnote: "Eine ganze Zahl im Beispiel wird `Int`, eine mit Komma `Double`. Wo nur `null` stand, lässt sich nichts raten — daraus wird `String?`."
            ) {
                KeyValueList(model.types.map { type in
                    KeyValueList.Item(type.name, "\(type.fields.count)")
                })
            }
        }

        InspectorNote(
            "Wie geraten wird",
            systemImage: "info.circle",
            footnote: "Aus einer Liste von Objekten entsteht ein Typ, in dem jedes Feld steht, das in irgendeinem Element vorkam — was nicht überall vorkam, wird optional. Das ist genau die Auskunft, die ein einzelnes Beispiel nicht hergibt."
        )
    }
}
