import AnvilKit
import Foundation

/// Eine Seitenauswahl, wie man sie in einen Druckdialog tippt.
public struct PageRange: Sendable, Hashable {
    /// Die Seiten, **nullbasiert** — so, wie PDFKit sie zählt.
    public let indices: [Int]

    public var isEmpty: Bool { indices.isEmpty }
    public var count: Int { indices.count }

    /// Liest eine Auswahl für ein Dokument mit `pageCount` Seiten.
    public init(parsing text: String, pageCount: Int) throws {
        guard pageCount > 0 else {
            self.indices = []
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            self.indices = Array(0..<pageCount)
            return
        }

        var collected: [Int] = []
        var seen: Set<Int> = []

        for part in trimmed.split(separator: ",") {
            let piece = part.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { continue }

            let bounds = try Self.bounds(piece, pageCount: pageCount)
            let range = bounds.lower <= bounds.upper
                ? bounds.lower...bounds.upper
                : bounds.upper...bounds.lower

            for page in range where page >= 1 && page <= pageCount {
                let index = page - 1
                if seen.insert(index).inserted { collected.append(index) }
            }
        }

        self.indices = collected
    }

    /// Direkt aus Nummern, ab 1 gezählt.
    public init(pages: [Int], pageCount: Int) {
        var seen: Set<Int> = []
        indices = pages
            .filter { $0 >= 1 && $0 <= pageCount }
            .map { $0 - 1 }
            .filter { seen.insert($0).inserted }
    }

    /// `8-` heißt „ab 8 bis zum Ende", `-3` heißt „bis 3".
    private static func bounds(_ piece: String, pageCount: Int) throws -> (lower: Int, upper: Int) {
        guard let dash = piece.firstIndex(of: "-") else {
            guard let page = Int(piece) else { throw notANumber(piece) }
            return (page, page)
        }

        let head = String(piece[piece.startIndex..<dash]).trimmingCharacters(in: .whitespaces)
        let tail = String(piece[piece.index(after: dash)...]).trimmingCharacters(in: .whitespaces)

        let lower: Int
        if head.isEmpty {
            lower = 1
        } else if let value = Int(head) {
            lower = value
        } else {
            throw notANumber(piece)
        }

        let upper: Int
        if tail.isEmpty {
            upper = pageCount
        } else if let value = Int(tail) {
            upper = value
        } else {
            throw notANumber(piece)
        }

        return (lower, upper)
    }

    static func notANumber(_ piece: String) -> AnvilError {
        AnvilError.invalidInput(
            localized("Seitenzahlen sehen so aus: 1-3, 5, 8- — das hier nicht: \(piece)")
        )
    }

    /// Die Auswahl wieder als Text, mit zusammengefassten Bereichen.
    public var text: String {
        guard !indices.isEmpty else { return "" }
        let pages = indices.sorted().map { $0 + 1 }

        var parts: [String] = []
        var start = pages[0]
        var previous = pages[0]

        for page in pages.dropFirst() {
            if page == previous + 1 {
                previous = page
                continue
            }
            parts.append(start == previous ? "\(start)" : "\(start)-\(previous)")
            start = page
            previous = page
        }
        parts.append(start == previous ? "\(start)" : "\(start)-\(previous)")
        return parts.joined(separator: ", ")
    }
}
