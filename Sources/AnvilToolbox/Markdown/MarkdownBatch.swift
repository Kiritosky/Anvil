import AnvilKit
import Foundation

/// Mehrere Markdown-Dateien auf einmal.
///
/// Der Grund, warum das ein eigener Typ ist und keine Schleife über die
/// Einzelansicht: Erst im Stapel lässt sich prüfen, was zwischen den Dateien
/// passiert. Ein Verweis von `README.md` auf `docs/aufbau.md#kern` ist aus der
/// Sicht von `README.md` nur ein Text — ob die Datei existiert und ob die
/// Sprungmarke darin vorkommt, weiß nur, wer beide kennt.
///
/// Genau daran gehen Dokumentationen kaputt: Eine Datei wird umbenannt, eine
/// Überschrift umformuliert, und die Verweise darauf zeigen ins Leere, ohne
/// dass irgendetwas rot wird.
public struct MarkdownBatch: Sendable {
    /// Ein Verweis, der ins Leere zeigt.
    public struct CrossProblem: Sendable, Hashable, Identifiable {
        public enum Kind: String, Sendable, Hashable {
            /// Die Datei liegt nicht im Stapel.
            case missingFile
            /// Die Datei gibt es, aber die Sprungmarke darin nicht.
            case missingAnchor

            public var title: String {
                switch self {
                case .missingFile: localized("Datei gibt es nicht")
                case .missingAnchor: localized("Sprungmarke in der Datei gibt es nicht")
                }
            }
        }

        public let id: Int
        public let kind: Kind
        /// Wohin der Verweis zeigt, unverändert.
        public let target: String
        public let line: Int
    }

    public struct Entry: Sendable, Identifiable {
        public let id: Int
        public let name: String
        public let document: MarkdownDocument
        /// Was innerhalb der Datei nicht stimmt.
        public let problems: [MarkdownDocument.Problem]
        /// Was zwischen den Dateien nicht stimmt.
        public let crossProblems: [CrossProblem]

        public var problemCount: Int { problems.count + crossProblems.count }
    }

    public let entries: [Entry]

    public var isEmpty: Bool { entries.isEmpty }
    public var problemCount: Int { entries.reduce(0) { $0 + $1.problemCount } }
    public var wordCount: Int { entries.reduce(0) { $0 + $1.document.statistics.words } }

    /// Liest einen Stapel.
    ///
    /// - Parameter files: Name und Inhalt. Der Name ist der, unter dem die
    ///   Datei in Verweisen auftaucht — bei einem abgelegten Ordner also der
    ///   Dateiname ohne Pfad.
    public init(_ files: [(name: String, text: String)]) {
        let documents = files.map { (name: $0.name, document: MarkdownDocument($0.text)) }

        // Erst alle Anker sammeln, dann prüfen: Ein Verweis auf eine Datei
        // weiter hinten im Stapel ist genauso gültig wie einer nach vorn.
        var anchorsByFile: [String: Set<String>] = [:]
        for file in documents {
            anchorsByFile[file.name] = Set(file.document.headings.map(\.anchor))
        }

        entries = documents.enumerated().map { index, file in
            Entry(
                id: index,
                name: file.name,
                document: file.document,
                problems: file.document.problems,
                crossProblems: Self.crossProblems(
                    in: file.document,
                    anchorsByFile: anchorsByFile
                )
            )
        }
    }

    /// Prüft die Verweise einer Datei gegen den Rest des Stapels.
    ///
    /// Geprüft wird nur, was auf eine Markdown-Datei zeigt. Ein Verweis auf
    /// ein Bild, eine Adresse im Netz oder eine Sprungmarke im eigenen
    /// Dokument geht hier niemanden etwas an — die erste Prüfung macht die
    /// Einzelansicht, die zweite gehört nicht hierher.
    static func crossProblems(
        in document: MarkdownDocument,
        anchorsByFile: [String: Set<String>]
    ) -> [CrossProblem] {
        var result: [CrossProblem] = []

        for link in document.links where !link.isImage && !link.isExternal && !link.isAnchor {
            let parts = link.target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            let path = String(parts.first ?? "")
            guard path.hasSuffix(".md") || path.hasSuffix(".markdown") else { continue }

            // Verglichen wird der Dateiname. Der Stapel kennt keine
            // Ordnerstruktur — „../docs/x.md" und „x.md" sind hier dieselbe
            // Datei, und das ist die ehrlichere Näherung, als so zu tun, als
            // wüsste man es besser.
            let name = URL(fileURLWithPath: path).lastPathComponent
            guard let anchors = anchorsByFile[name] else {
                result.append(
                    CrossProblem(
                        id: result.count,
                        kind: .missingFile,
                        target: link.target,
                        line: link.line
                    )
                )
                continue
            }

            guard parts.count == 2, !parts[1].isEmpty else { continue }
            let anchor = String(parts[1])
            guard !anchors.contains(anchor) else { continue }
            result.append(
                CrossProblem(
                    id: result.count,
                    kind: .missingAnchor,
                    target: link.target,
                    line: link.line
                )
            )
        }
        return result
    }

    // MARK: - Ausgeben

    /// Eine Zeile je Datei, tabulatorgetrennt.
    public var report: String {
        let header = [
            localized("Datei"),
            localized("Wörter"),
            localized("Überschriften"),
            localized("Links"),
            localized("Beanstandungen")
        ].joined(separator: "\t")

        let rows = entries.map { entry in
            let statistics = entry.document.statistics
            return [
                entry.name,
                "\(statistics.words)",
                "\(statistics.headings)",
                "\(statistics.links)",
                "\(entry.problemCount)"
            ].joined(separator: "\t")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    /// Alle Beanstandungen, eine je Zeile — das, was man in ein Ticket klebt.
    public var problemReport: String {
        var lines: [String] = []
        for entry in entries {
            for problem in entry.problems {
                lines.append([entry.name, "\(problem.line)", problem.kind.title, problem.detail]
                    .joined(separator: "\t"))
            }
            for problem in entry.crossProblems {
                lines.append([entry.name, "\(problem.line)", problem.kind.title, problem.target]
                    .joined(separator: "\t"))
            }
        }
        return lines.joined(separator: "\n")
    }
}
