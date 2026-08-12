import AnvilKit
import Foundation

/// Viele Konfigurationsdateien auf einmal umwandeln.
///
/// Der Anlass ist immer derselbe: Ein Projekt zieht von YAML nach TOML um, oder
/// eine Werkzeugkette will JSON, wo bisher YAML lag. Einzeln ist das eine
/// Viertelstunde Copy-and-paste, bei der man in der zwölften Datei nicht mehr
/// hinsieht.
///
/// Wie beim Umbenennen und beim Ersetzen: erst der Plan, dann die Tat. Der
/// Plan sagt vorher, welche Datei wohin geschrieben würde und welche im Weg
/// steht.
public struct StructuredBatch: Sendable {
    /// Warum eine Datei nicht geschrieben wird.
    public enum Problem: Sendable, Hashable {
        /// Der Inhalt ließ sich nicht lesen.
        case unreadable(String)
        /// Quelle und Ziel sind dasselbe Format.
        case sameFormat
        /// Am Ziel liegt schon eine Datei.
        case occupied

        public var title: String {
            switch self {
            case .unreadable: localized("nicht lesbar")
            case .sameFormat: localized("schon in diesem Format")
            case .occupied: localized("Datei gibt es schon")
            }
        }

        /// Der Grund im Klartext, soweit einer bekannt ist.
        public var detail: String {
            switch self {
            case let .unreadable(reason): reason
            default: title
            }
        }
    }

    public struct Entry: Sendable, Identifiable {
        public let url: URL
        /// Woran das Format erkannt wurde.
        public let source: StructuredFormat
        /// Der fertige Text im Zielformat. Nur vorhanden, wenn es geht.
        public let converted: String?
        public let problem: Problem?

        public var id: String { url.path }
        public var name: String { url.lastPathComponent }
        public var willWrite: Bool { problem == nil && converted != nil }

        public init(
            url: URL,
            source: StructuredFormat,
            converted: String?,
            problem: Problem?
        ) {
            self.url = url
            self.source = source
            self.converted = converted
            self.problem = problem
        }

        /// Wohin geschrieben würde: derselbe Name, neue Endung.
        public func destination(_ target: StructuredFormat) -> URL {
            url.deletingPathExtension().appendingPathExtension(target.fileExtension)
        }
    }

    public let entries: [Entry]
    public let target: StructuredFormat

    public var writing: [Entry] { entries.filter(\.willWrite) }
    public var blocked: [Entry] { entries.filter { $0.problem != nil } }
    public var isReady: Bool { !writing.isEmpty }
    public var isEmpty: Bool { entries.isEmpty }

    public static let empty = StructuredBatch(entries: [], target: .json)

    init(entries: [Entry], target: StructuredFormat) {
        self.entries = entries
        self.target = target
    }

    // MARK: - Planen

    /// Baut den Plan aus Name und Inhalt — der Teil ohne Dateisystem.
    ///
    /// - Parameter existing: Welche Zielpfade es schon gibt. Ohne diese
    ///   Auskunft kann der Plan nicht sehen, dass er etwas überschreiben
    ///   würde — und das fällt sonst erst auf, wenn es passiert ist.
    public init(
        files: [(url: URL, text: String)],
        target: StructuredFormat,
        existing: Set<String> = []
    ) {
        let entries = files.map { file -> Entry in
            let source = StructuredFormat.detect(name: file.url.lastPathComponent, text: file.text)
            guard source != target else {
                return Entry(url: file.url, source: source, converted: nil, problem: .sameFormat)
            }
            do {
                let value = try source.read(file.text)
                let converted = target.write(value)
                let destination = file.url
                    .deletingPathExtension()
                    .appendingPathExtension(target.fileExtension)
                let problem: Problem? = existing.contains(destination.path) ? .occupied : nil
                return Entry(url: file.url, source: source, converted: converted, problem: problem)
            } catch {
                return Entry(
                    url: file.url,
                    source: source,
                    converted: nil,
                    problem: .unreadable(AnvilError.wrapping(error).message)
                )
            }
        }
        self.init(entries: entries, target: target)
    }

    /// Liest die Dateien selbst und baut daraus den Plan.
    public init(urls: [URL], target: StructuredFormat) {
        var files: [(url: URL, text: String)] = []
        var unreadable: [Entry] = []

        for url in urls {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                files.append((url, text))
            } else {
                unreadable.append(
                    Entry(
                        url: url,
                        source: .json,
                        converted: nil,
                        problem: .unreadable(localized("Die Datei ist kein UTF-8-Text."))
                    )
                )
            }
        }

        // Was am Ziel schon liegt, wird einmal für alle nachgesehen.
        let manager = FileManager.default
        let destinations = files.map {
            $0.url.deletingPathExtension().appendingPathExtension(target.fileExtension).path
        }
        let existing = Set(destinations.filter { manager.fileExists(atPath: $0) })

        let planned = StructuredBatch(files: files, target: target, existing: existing)
        self.init(entries: planned.entries + unreadable, target: target)
    }

    // MARK: - Ausgeben

    public static let reportColumns = [
        localized("Datei"),
        localized("Erkannt"),
        localized("Wird zu"),
        localized("Hinweis")
    ]

    public func row(_ entry: Entry) -> [String] {
        [
            entry.name,
            entry.source.title,
            entry.willWrite ? entry.destination(target).lastPathComponent : "—",
            entry.problem?.title ?? "—"
        ]
    }

    public var report: String {
        let header = Self.reportColumns.joined(separator: "\t")
        return ([header] + entries.map { row($0).joined(separator: "\t") }).joined(separator: "\n")
    }

    // MARK: - Ausführen

    public struct Outcome: Sendable {
        public let written: Int
        /// Die geschriebenen Dateien — zum Zurücknehmen.
        public let created: [URL]
    }

    /// Schreibt die umgewandelten Dateien neben die Quellen.
    ///
    /// Die Quelldateien bleiben unangetastet. Eine Umwandlung, die das
    /// Original wegnimmt, wäre nicht rückgängig zu machen, sobald jemand die
    /// neue Datei einmal angefasst hat.
    @discardableResult
    public func execute() throws -> Outcome {
        guard isReady else {
            throw AnvilError.invalidInput(
                localized("Es gibt nichts umzuwandeln. Erst muss eine Datei dabei sein, die sich lesen lässt.")
            )
        }

        var created: [URL] = []
        for entry in writing {
            guard let converted = entry.converted else { continue }
            let destination = entry.destination(target)
            try converted.write(to: destination, atomically: true, encoding: .utf8)
            created.append(destination)
        }
        return Outcome(written: created.count, created: created)
    }

    /// Nimmt zurück, was ``execute()`` angelegt hat.
    ///
    /// Gelöscht wird nur, was in diesem Durchgang entstanden ist — eine Datei,
    /// die vorher schon da war, kam nie in die Liste.
    public static func revert(_ created: [URL]) throws {
        for url in created {
            try FileManager.default.removeItem(at: url)
        }
    }
}
