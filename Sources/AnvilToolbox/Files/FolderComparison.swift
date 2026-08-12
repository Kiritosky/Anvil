import AnvilKit
import Foundation

/// Zwei Ordner nebeneinander.
///
/// Die Frage dahinter ist immer dieselbe und immer unangenehm: Ist die
/// Sicherung vollständig? Der Finder beantwortet sie nicht — er zeigt zwei
/// Fenster, und ob in dem einen dieselben tausend Dateien liegen wie im
/// anderen, sieht man daran nicht.
///
/// Verglichen wird über den Pfad *unterhalb* der beiden Ordner: `bilder/2026/
/// anna.jpg` heißt in beiden dasselbe, auch wenn die Ordner darüber anders
/// heißen. Der Inhalt kommt erst dran, wenn die Größe gleich ist — bei
/// verschiedener Größe steht das Ergebnis schon fest.
public struct FolderComparison: Sendable {
    public enum Difference: String, Sendable, Hashable, CaseIterable, Identifiable {
        /// Gibt es nur links.
        case onlyLeft
        /// Gibt es nur rechts.
        case onlyRight
        /// Gibt es in beiden, aber verschieden.
        case different
        /// Gibt es in beiden und gleich.
        case same

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .onlyLeft: localized("nur links")
            case .onlyRight: localized("nur rechts")
            case .different: localized("verschieden")
            case .same: localized("gleich")
            }
        }

        public var systemImage: String {
            switch self {
            case .onlyLeft: "arrow.left"
            case .onlyRight: "arrow.right"
            case .different: "not.equal"
            case .same: "equal"
            }
        }

        /// Ob es der Grund ist, warum man vergleicht.
        public var isNoteworthy: Bool { self != .same }
    }

    public struct Entry: Sendable, Hashable, Identifiable {
        /// Der Pfad unterhalb der beiden Ordner.
        public let path: String
        public let difference: Difference
        public let leftSize: Int?
        public let rightSize: Int?

        public var id: String { path }
        public var name: String { URL(fileURLWithPath: path).lastPathComponent }

        public init(path: String, difference: Difference, leftSize: Int?, rightSize: Int?) {
            self.path = path
            self.difference = difference
            self.leftSize = leftSize
            self.rightSize = rightSize
        }
    }

    public let entries: [Entry]

    public var isEmpty: Bool { entries.isEmpty }
    public func entries(_ difference: Difference) -> [Entry] {
        entries.filter { $0.difference == difference }
    }

    public var noteworthy: [Entry] { entries.filter(\.difference.isNoteworthy) }
    public var isIdentical: Bool { !entries.isEmpty && noteworthy.isEmpty }

    public static let empty = FolderComparison(entries: [])

    init(entries: [Entry]) {
        self.entries = entries
    }

    // MARK: - Vergleichen

    /// - Parameters:
    ///   - left: Pfad unterhalb des linken Ordners und Größe.
    ///   - right: dasselbe für rechts.
    ///   - sameContent: Wird nur gefragt, wenn es die Datei auf beiden Seiten
    ///     gibt und sie gleich groß ist. Als Parameter, damit sich der
    ///     Vergleich prüfen lässt, ohne dass etwas von der Platte gelesen wird.
    public init(
        left: [(path: String, size: Int)],
        right: [(path: String, size: Int)],
        sameContent: (String) -> Bool
    ) {
        var leftSizes: [String: Int] = [:]
        for file in left { leftSizes[file.path] = file.size }
        var rightSizes: [String: Int] = [:]
        for file in right { rightSizes[file.path] = file.size }

        var entries: [Entry] = []
        for path in Set(leftSizes.keys).union(rightSizes.keys) {
            let leftSize = leftSizes[path]
            let rightSize = rightSizes[path]

            let difference: Difference
            switch (leftSize, rightSize) {
            case (.some, .none): difference = .onlyLeft
            case (.none, .some): difference = .onlyRight
            case let (.some(a), .some(b)):
                // Verschiedene Größe heißt verschiedener Inhalt — dafür muss
                // niemand etwas lesen.
                difference = a != b ? .different : (sameContent(path) ? .same : .different)
            case (.none, .none): continue
            }

            entries.append(
                Entry(path: path, difference: difference, leftSize: leftSize, rightSize: rightSize)
            )
        }

        // Erst das Auffällige, darin nach Pfad — eine Liste, in der man von
        // oben nach unten liest und irgendwann aufhören kann.
        self.init(entries: entries.sorted { first, second in
            if first.difference.isNoteworthy != second.difference.isNoteworthy {
                return first.difference.isNoteworthy
            }
            return first.path < second.path
        })
    }

    // MARK: - Ausgeben

    public static let reportColumns = [
        localized("Pfad"),
        localized("Zustand"),
        localized("Links"),
        localized("Rechts")
    ]

    public func rows(_ shown: [Entry]) -> [[String]] {
        shown.map { entry in
            [
                entry.path,
                entry.difference.title,
                entry.leftSize.map(StoredData.size) ?? "—",
                entry.rightSize.map(StoredData.size) ?? "—"
            ]
        }
    }

    public var report: String {
        let header = Self.reportColumns.joined(separator: "\t")
        return ([header] + rows(entries).map { $0.joined(separator: "\t") })
            .joined(separator: "\n")
    }
}
