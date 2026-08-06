import AnvilKit
import AnvilUI
import Foundation
import SwiftUI

/// Try a regular expression against real text and see what it matches.
///
/// The one tool in the deterministic set that cannot be a plain
/// `String -> String` function: it has two inputs (pattern and subject), a
/// handful of flags, and the interesting output is *where* things matched
/// rather than a transformed string.
public struct RegexToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var pattern = ""
    @State private var subject = ""
    @State private var replacement = ""
    @State private var isCaseInsensitive = false
    @State private var spansLines = false
    @State private var dotMatchesNewlines = false
    @State private var dropError: AnvilError?
    @State private var orientation: WorkbenchOrientation = .vertical

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
            subject = text
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: AnvilSpacing.md) {
            patternField

            ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
                subjectPane
            } secondary: {
                resultPane
            } status: {
                statusBar
            }
        }
    }

    private var patternField: some View {
        HStack(spacing: AnvilSpacing.sm) {
            Text(verbatim: "/")
                .font(AnvilFont.mono)
                .foregroundStyle(AnvilColor.textTertiary)

            AnvilTextField(
                text: $pattern,
                placeholder: "Muster, z. B. \\b\\w+@\\w+\\.\\w+\\b",
                isMonospaced: true
            )

            Text(verbatim: "/\(flagSuffix)")
                .font(AnvilFont.mono)
                .foregroundStyle(AnvilColor.textTertiary)

            if case let .failure(message) = evaluation {
                StatusPill(.resolved(message), systemImage: "exclamationmark.triangle", tone: .danger)
            } else if case let .success(result) = evaluation, !pattern.isEmpty {
                StatusPill(
                    "\(result.matches.count) Treffer",
                    systemImage: result.matches.isEmpty ? "circle" : "checkmark",
                    tone: result.matches.isEmpty ? .neutral : .success
                )
            }
        }
    }

    private var subjectPane: some View {
        AnvilPane("Testtext", systemImage: "text.alignleft") {
            AnvilTextEditor(
                text: $subject,
                placeholder: "Text, gegen den das Muster laufen soll …",
                isMonospaced: true
            )
        } accessory: {
            Button { subject = context.pasteboard.string() ?? subject } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp("Einfügen")
        }
    }

    private var resultPane: some View {
        AnvilPane(
            replacement.isEmpty ? "Treffer" : "Ersetzt",
            systemImage: replacement.isEmpty ? "text.magnifyingglass" : "arrow.triangle.2.circlepath",
            tone: .neutral
        ) {
            switch evaluation {
            case let .failure(message):
                EmptyStateView(
                    title: "Muster ist ungültig",
                    message: .resolved(message),
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            case .idle:
                EmptyStateView(
                    title: "Kein Muster",
                    message: "Trag oben einen regulären Ausdruck ein — Treffer erscheinen sofort.",
                    systemImage: "asterisk"
                )
            case let .success(result):
                if !replacement.isEmpty {
                    AnvilTextView(result.replaced, isMonospaced: true)
                } else if result.matches.isEmpty {
                    EmptyStateView(
                        title: "Keine Treffer",
                        message: "Das Muster passt auf keine Stelle im Testtext.",
                        systemImage: "magnifyingglass"
                    )
                } else {
                    matchList(result)
                }
            }
        } accessory: {
            CopyButton(text: copyableResult)
        }
    }

    private func matchList(_ result: RegexEvaluation) -> some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: AnvilSpacing.sm) {
                ForEach(result.matches) { match in
                    VStack(alignment: .leading, spacing: AnvilSpacing.xs) {
                        HStack(spacing: AnvilSpacing.sm) {
                            StatusPill(.resolved("#\(match.index + 1)"), tone: .accent)
                            Text(verbatim: match.text)
                                .font(AnvilFont.mono)
                                .foregroundStyle(AnvilColor.textPrimary)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                            Text(verbatim: "\(match.location)…\(match.location + match.length)")
                                .font(AnvilFont.caption.monospacedDigit())
                                .foregroundStyle(AnvilColor.textTertiary)
                        }

                        if !match.groups.isEmpty {
                            KeyValueList(
                                match.groups.enumerated().map { index, value in
                                    KeyValueList.Item(
                                        localized("Gruppe \(index + 1)"),
                                        value.isEmpty ? "—" : value
                                    )
                                }
                            )
                        }
                    }
                    .padding(AnvilSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                            .fill(AnvilColor.surface)
                    }
                }
            }
            .padding(AnvilSpacing.md)
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            if case let .success(result) = evaluation {
                StatusMetric("\(result.matches.count)", label: "Treffer", systemImage: "text.magnifyingglass")
                let groups = result.matches.first?.groups.count ?? 0
                if groups > 0 {
                    StatusMetric("\(groups)", label: "Gruppen", systemImage: "parentheses")
                }
            }
            StatusMetric("\(subject.count)", label: "Zeichen", systemImage: "character")
        } trailing: {
            StatusPill(.resolved(flagSummary), systemImage: "flag", tone: .neutral)
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection("Schalter", systemImage: "flag") {
            Toggle("Groß-/Kleinschreibung egal", isOn: $isCaseInsensitive)
                .font(AnvilFont.body)
            Toggle("^ und $ je Zeile", isOn: $spansLines)
                .font(AnvilFont.body)
            Toggle(". trifft auch Zeilenumbrüche", isOn: $dotMatchesNewlines)
                .font(AnvilFont.body)
        }

        InspectorSection(
            "Ersetzen",
            systemImage: "arrow.triangle.2.circlepath",
            footnote: "Leer lassen, um nur zu suchen. $1, $2 … setzen die Klammergruppen ein."
        ) {
            AnvilTextField(text: $replacement, placeholder: "Ersatztext", isMonospaced: true)
        }

        InspectorSection("Bausteine", systemImage: "book") {
            KeyValueList([
                KeyValueList.Item(localized("Ziffer"), "\\d"),
                KeyValueList.Item(localized("Wortzeichen"), "\\w"),
                KeyValueList.Item(localized("Leerraum"), "\\s"),
                KeyValueList.Item(localized("Wortgrenze"), "\\b"),
                KeyValueList.Item(localized("Beliebig oft"), "*"),
                KeyValueList.Item(localized("Mindestens eins"), "+"),
                KeyValueList.Item(localized("Optional"), "?"),
                KeyValueList.Item(localized("Gruppe"), "( … )"),
                KeyValueList.Item(localized("Auswahl"), "a|b")
            ])
        }
    }

    // MARK: - Evaluation

    private enum Evaluation {
        case idle
        case success(RegexEvaluation)
        case failure(String)
    }

    private var evaluation: Evaluation {
        guard !pattern.isEmpty else { return .idle }
        do {
            return .success(
                try RegexEvaluation(
                    pattern: pattern,
                    subject: subject,
                    replacement: replacement,
                    options: regexOptions
                )
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private var regexOptions: NSRegularExpression.Options {
        var options: NSRegularExpression.Options = []
        if isCaseInsensitive { options.insert(.caseInsensitive) }
        if spansLines { options.insert(.anchorsMatchLines) }
        if dotMatchesNewlines { options.insert(.dotMatchesLineSeparators) }
        return options
    }

    /// The flag letters shown after the closing slash, like in other tools.
    private var flagSuffix: String {
        var flags = ""
        if isCaseInsensitive { flags += "i" }
        if spansLines { flags += "m" }
        if dotMatchesNewlines { flags += "s" }
        return flags
    }

    private var flagSummary: String {
        flagSuffix.isEmpty ? localized("keine Schalter") : "/\(flagSuffix)"
    }

    private var copyableResult: String {
        guard case let .success(result) = evaluation else { return "" }
        if !replacement.isEmpty { return result.replaced }
        return result.matches.map(\.text).joined(separator: "\n")
    }
}

/// The result of running a pattern over a subject.
struct RegexEvaluation {
    struct Match: Identifiable {
        let id = UUID()
        let index: Int
        let text: String
        let location: Int
        let length: Int
        /// Capture groups, in order, empty string where a group did not match.
        let groups: [String]
    }

    let matches: [Match]
    let replaced: String

    init(
        pattern: String,
        subject: String,
        replacement: String,
        options: NSRegularExpression.Options
    ) throws {
        let expression = try NSRegularExpression(pattern: pattern, options: options)
        let range = NSRange(subject.startIndex..., in: subject)

        matches = expression.matches(in: subject, options: [], range: range)
            .enumerated()
            .map { index, match in
                let groups = (1..<match.numberOfRanges).map { groupIndex -> String in
                    guard let groupRange = Range(match.range(at: groupIndex), in: subject) else {
                        return ""
                    }
                    return String(subject[groupRange])
                }

                let text = Range(match.range, in: subject).map { String(subject[$0]) } ?? ""
                return Match(
                    index: index,
                    text: text,
                    location: match.range.location,
                    length: match.range.length,
                    groups: groups
                )
            }

        replaced = replacement.isEmpty
            ? subject
            : expression.stringByReplacingMatches(
                in: subject,
                options: [],
                range: range,
                withTemplate: replacement
            )
    }
}
