import AnvilKit
import AnvilUI
import SwiftUI

/// JSON, YAML und TOML ineinander umwandeln.
public struct StructuredToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    /// Welches Format gemeint ist.
    /// Nicht `private`: die Erkennung wird geprüft, und dafür muss der
    /// Typ ihres Ergebnisses sichtbar sein.
    enum Format: String, Hashable, CaseIterable, Identifiable {
        case json
        case yaml
        case toml

        var id: String { rawValue }

        var title: String {
            switch self {
            case .json: "JSON"
            case .yaml: "YAML"
            case .toml: "TOML"
            }
        }

        var systemImage: String {
            switch self {
            case .json: "curlybraces"
            case .yaml: "list.bullet.indent"
            case .toml: "square.split.1x2"
            }
        }
    }

    @State private var input = ""
    @State private var chosenInput: Format?
    @State private var output: Format = .json
    @State private var value: StructuredValue?
    @State private var error: AnvilError?
    @State private var detected: Format = .json
    @State private var dropError: AnvilError?
    @State private var orientation: WorkbenchOrientation = .horizontal

    public init(context: ToolContext, metadata: ToolMetadata) {
        self.context = context
        self.metadata = metadata
    }

    public var body: some View {
        ToolScaffold(metadata: metadata) {
            content
        } inspector: {
            inspector
        } actions: {
            WorkbenchOrientationPicker(orientation: $orientation)
        }
        .anvilErrorBanner($dropError)
        .anvilFileDrop(.text, error: $dropError) { dropped in
            guard case let .text(text, _) = dropped else { return }
            input = text
            chosenInput = nil
        }
        .onAppear {
            restore()
            read()
        }
        .onDisappear(perform: remember)
        .onChange(of: input) { read() }
        .onChange(of: chosenInput) { read() }
    }

    private func restore() {
        if let handed = context.handoff.take(for: metadata.id) {
            input = handed
            // Ein hereingereichter Text bringt sein eigenes Format mit; eine
            // Wahl von vorhin wäre jetzt die falsche.
            chosenInput = nil
            return
        }
        guard let draft = context.drafts.draft(for: metadata.id) else { return }
        input = draft.input
    }

    private func remember() {
        context.drafts.save(
            DraftStore.Draft(input: input),
            for: metadata.id,
            allowed: context.settings[.remembersInput]
        )
    }

    // MARK: - Lesen

    private func read() {
        detected = Self.detect(input)
        let format = chosenInput ?? detected

        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            value = nil
            error = nil
            return
        }

        do {
            switch format {
            case .json: value = try StructuredValue.json(parsing: input)
            case .yaml: value = try StructuredValue.yaml(parsing: input)
            case .toml: value = try StructuredValue.toml(parsing: input)
            }
            error = nil
        } catch {
            value = nil
            self.error = AnvilError.wrapping(error)
        }
    }

    /// Rät das Format am Anfang des Textes.
    ///
    /// Drei Anhaltspunkte, in dieser Reihenfolge: Eine geschweifte oder eckige
    /// Klammer am Anfang ist JSON. Eine Zeile in eckigen Klammern oder ein
    /// Gleichheitszeichen vor dem ersten Doppelpunkt ist TOML. Sonst YAML —
    /// das Format, das am wenigsten verlangt.
    static func detect(_ text: String) -> Format {
        let lines = TextLines.split(text, keepingEmpty: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard let first = lines.first else { return .json }

        if first.hasPrefix("{") { return .json }
        if first.hasPrefix("[") {
            // `[server.http]` ist eine TOML-Tabelle, `[1, 2]` eine
            // JSON-Liste. Unterscheiden lässt sich das nur am Inhalt der
            // Klammer: in einer Tabelle steht ein Schlüssel und sonst nichts.
            let inner = first.dropFirst().drop { $0 == "[" }.prefix { $0 != "]" }
            let looksLikeTable = !inner.isEmpty && inner.allSatisfy {
                $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." || $0 == "\""
            }
            return looksLikeTable ? .toml : .json
        }
        for line in lines.prefix(20) {
            if line.hasPrefix("[") { return .toml }
            guard let equals = line.firstIndex(of: "=") else { continue }
            // `a = 1` ist TOML, `a: 1` ist YAML. Es zählt, was zuerst kommt.
            guard let colon = line.firstIndex(of: ":") else { return .toml }
            if equals < colon { return .toml }
        }
        return .yaml
    }

    private var outputText: String {
        guard let value else { return "" }
        switch output {
        case .json: return value.jsonText
        case .yaml: return value.yamlText
        case .toml: return value.tomlText
        }
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
            inputPane
        } secondary: {
            resultPane
        } status: {
            statusBar
        }
    }

    private var inputPane: some View {
        AnvilPane(.resolved((chosenInput ?? detected).title), systemImage: (chosenInput ?? detected).systemImage) {
            AnvilTextEditor(
                text: $input,
                placeholder: "name: Anvil\nwerkzeuge:\n  - Tabellen\n  - Netzrechner",
                isMonospaced: true
            )
        } accessory: {
            Button { input = context.pasteboard.string() ?? input } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp("Einfügen")
        }
    }

    @ViewBuilder
    private var resultPane: some View {
        AnvilPane(.resolved(output.title), systemImage: output.systemImage, tone: .neutral) {
            if let error {
                VStack {
                    AnvilBanner(error: error)
                    Spacer(minLength: 0)
                }
                .padding(AnvilSpacing.md)
            } else if value == nil {
                EmptyStateView(
                    title: "Noch nichts da",
                    message: "JSON, YAML oder TOML einwerfen — das Format erkennt Anvil selbst.",
                    systemImage: "arrow.left.arrow.right"
                )
            } else {
                AnvilTextView(outputText, isMonospaced: true)
            }
        } accessory: {
            HStack(spacing: AnvilSpacing.xs) {
                HandoffMenu(context: context, from: metadata.id, text: outputText)
                CopyButton(text: outputText)
            }
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            if let value {
                StatusMetric("\(value.count)", label: "Werte", systemImage: "number")
                StatusMetric("\(value.depth)", label: "Ebenen", systemImage: "list.bullet.indent")
            }
        } trailing: {
            StatusPill(
                .resolved((chosenInput ?? detected).title),
                systemImage: chosenInput == nil ? "wand.and.rays" : "text.cursor",
                tone: .neutral
            )
        }
    }

    // MARK: - Inspector

    /// „Automatisch" steht als leere Wahl vorne.
    private static let inputChoices: [Format?] = [nil] + Format.allCases.map(Optional.init)

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Eingabe",
            systemImage: "arrow.down.doc",
            footnote: "Eine Klammer am Anfang ist JSON, eine Zeile in eckigen Klammern TOML, sonst YAML."
        ) {
            ChipPicker(
                selection: $chosenInput,
                options: Self.inputChoices,
                title: { $0?.title ?? localized("Automatisch") }
            )
        }

        InspectorSection(
            "Ausgabe",
            systemImage: "arrow.up.doc",
            footnote: "Nicht ausgelegt werden: YAML-Anker und -Verweise (& und *) und Typangaben (!!); Datum und Uhrzeit aus TOML bleiben Text, weil JSON dafür nichts hat. Verloren geht davon nichts — es bleibt stehen, wie es dasteht."
        ) {
            ChipPicker(
                selection: $output,
                options: Format.allCases,
                title: { $0.title },
                systemImage: { $0.systemImage }
            )
        }
    }
}
