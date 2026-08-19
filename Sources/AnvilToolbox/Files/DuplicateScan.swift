import AnvilKit
import Foundation

/// Dieselbe Datei, mehrfach auf der Platte.
public struct DuplicateScan: Sendable {
    public struct File: Sendable, Hashable, Identifiable {
        public let url: URL
        public let size: Int

        public var id: String { url.path }
        public var name: String { url.lastPathComponent }
        public var folder: String { url.deletingLastPathComponent().path }

        public init(url: URL, size: Int) {
            self.url = url
            self.size = size
        }
    }

    /// Dateien mit demselben Inhalt.
    public struct Group: Sendable, Identifiable {
        /// Die Prüfsumme, an der es hängt.
        public let digest: String
        /// Immer mindestens zwei, sonst wäre es keine Gruppe.
        public let files: [File]

        public var id: String { digest }
        public var size: Int { files.first?.size ?? 0 }
        public var count: Int { files.count }

        /// Was frei würde, wenn nur eine bliebe.
        public var wastedBytes: Int { size * (files.count - 1) }

        public init(digest: String, files: [File]) {
            self.digest = digest
            self.files = files
        }
    }

    public let groups: [Group]
    /// Wie viele Dateien überhaupt angesehen wurden.
    public let examined: Int
    /// Bei wie vielen die Prüfsumme über die ganze Datei nötig war.
    public let hashed: Int
    /// Bei wie vielen ein Blick auf den Anfang gereicht hat.
    public let peeked: Int

    public var isEmpty: Bool { groups.isEmpty }
    public var duplicateCount: Int { groups.reduce(0) { $0 + $1.count - 1 } }
    public var wastedBytes: Int { groups.reduce(0) { $0 + $1.wastedBytes } }

    public static let empty = DuplicateScan(groups: [], examined: 0, hashed: 0, peeked: 0)

    public init(groups: [Group], examined: Int, hashed: Int, peeked: Int = 0) {
        self.groups = groups
        self.examined = examined
        self.hashed = hashed
        self.peeked = peeked
    }

    // MARK: - Suchen

    /// Die erste Stufe: nach Größe gruppieren, Einzelgänger wegwerfen.
    static func candidates(_ files: [File]) -> [[File]] {
        var bySize: [Int: [File]] = [:]
        for file in files where file.size > 0 {
            bySize[file.size, default: []].append(file)
        }
        return bySize
            .filter { $0.value.count > 1 }
            .sorted { $0.key > $1.key }
            .map(\.value)
    }

    /// Die zweite Stufe: der schnelle Blick auf den Anfang der Datei.
    public static func scan(
        _ files: [File],
        peek: ((URL) throws -> String)? = nil,
        digest: (URL) throws -> String
    ) -> DuplicateScan {
        var groups: [Group] = []
        var hashed = 0
        var peeked = 0

        for candidate in candidates(files) {
            for narrowed in narrow(candidate, peek: peek, counter: &peeked) {
                var byDigest: [String: [File]] = [:]
                for file in narrowed {
                    guard let value = try? digest(file.url) else { continue }
                    hashed += 1
                    byDigest[value, default: []].append(file)
                }

                for (value, same) in byDigest where same.count > 1 {
                    groups.append(
                        Group(digest: value, files: same.sorted { $0.url.path < $1.url.path })
                    )
                }
            }
        }

        groups.sort { $0.wastedBytes > $1.wastedBytes }
        return DuplicateScan(
            groups: groups,
            examined: files.count,
            hashed: hashed,
            peeked: peeked
        )
    }

    /// Teilt eine Größengruppe nach dem Anfang der Dateien auf.
    private static func narrow(
        _ candidate: [File],
        peek: ((URL) throws -> String)?,
        counter: inout Int
    ) -> [[File]] {
        guard let peek else { return [candidate] }

        var byPrefix: [String: [File]] = [:]
        for file in candidate {
            guard let value = try? peek(file.url) else { continue }
            counter += 1
            byPrefix[value, default: []].append(file)
        }
        return byPrefix.values.filter { $0.count > 1 }
    }

    // MARK: - Ausgeben

    public static let reportColumns = [
        localized("Datei"),
        localized("Ordner"),
        localized("Größe"),
        localized("Gleiche")
    ]

    public func rows() -> [[String]] {
        groups.flatMap { group in
            group.files.map { file in
                [
                    file.name,
                    file.folder,
                    StoredData.size(file.size),
                    "\(group.count)"
                ]
            }
        }
    }

    public var report: String {
        let header = Self.reportColumns.joined(separator: "\t")
        return ([header] + rows().map { $0.joined(separator: "\t") }).joined(separator: "\n")
    }

    /// Die Befehle, mit denen sich die Dubletten entfernen ließen — je Gruppe
    /// bleibt die erste Datei stehen.
    public var removalCommands: String {
        groups.flatMap { group in
            group.files.dropFirst().map { file in
                "rm \(Shell.quoted(file.url.path))"
            }
        }
        .joined(separator: "\n")
    }
}
