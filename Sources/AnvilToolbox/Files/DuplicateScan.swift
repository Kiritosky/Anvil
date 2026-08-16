import AnvilKit
import Foundation

/// Dieselbe Datei, mehrfach auf der Platte.
///
/// Die Frage stellt sich, wenn eine Platte voll ist oder ein Ordner über
/// Jahre gewachsen ist: Was liegt hier doppelt? Von Hand ist sie nicht zu
/// beantworten — gleiche Dateien heißen selten gleich, und gleiche Namen
/// bedeuten selten dasselbe.
///
/// Gesucht wird in drei Stufen, und das ist der ganze Trick. Erst nach Größe
/// gruppieren: Zwei Dateien unterschiedlicher Größe können nie gleich sein,
/// und in einem Ordner mit zehntausend Dateien bleibt danach fast nichts
/// übrig. Dann ein Blick auf die ersten vierundsechzig Kilobyte, der zwei
/// zufällig gleich große Videos in aller Regel schon auseinanderhält. Erst was
/// beides übersteht, wird ganz gelesen.
///
/// Wer stattdessen alles durchrechnet, liest das ganze Verzeichnis — und das
/// dauert bei Videos Minuten.
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
    ///
    /// Leere Dateien bleiben draußen. Sie sind alle gleich, und eine Meldung
    /// „diese 240 leeren Dateien sind Dubletten" hilft niemandem.
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
    ///
    /// Zwei Videos von vier Gigabyte, die zufällig gleich groß sind,
    /// unterscheiden sich fast immer schon im ersten Block. Sie ganz zu lesen,
    /// um das festzustellen, sind acht Gigabyte für eine Antwort, die nach
    /// vierundsechzig Kilobyte feststand.
    ///
    /// - Parameters:
    ///   - peek: Die Prüfsumme über den Anfang. Fehlt sie, entfällt die Stufe.
    ///   - digest: Die Prüfsumme über die ganze Datei. Beides als Parameter,
    ///     damit sich die Suche prüfen lässt, ohne dass etwas von der Platte
    ///     gelesen wird.
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

        // Das Größte zuerst: Danach fragt, wer Platz sucht.
        groups.sort { $0.wastedBytes > $1.wastedBytes }
        return DuplicateScan(
            groups: groups,
            examined: files.count,
            hashed: hashed,
            peeked: peeked
        )
    }

    /// Teilt eine Größengruppe nach dem Anfang der Dateien auf.
    ///
    /// Was danach allein dasteht, wird nie ganz gelesen — und genau das ist
    /// der Gewinn.
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
    ///
    /// Ausgeführt wird hier nichts. Eine App, die ungefragt Dateien löscht,
    /// müsste sich sicherer sein, als sie sein kann: Zwei Dateien mit
    /// gleichem Inhalt können trotzdem beide gebraucht werden — von einem
    /// Programm, das seine Datei am Ort erwartet, oder von einem Menschen,
    /// der die Kopie im anderen Ordner mit Absicht dort abgelegt hat.
    public var removalCommands: String {
        groups.flatMap { group in
            group.files.dropFirst().map { file in
                "rm \(Shell.quoted(file.url.path))"
            }
        }
        .joined(separator: "\n")
    }
}
