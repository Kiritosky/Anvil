import AnvilKit
import Foundation
import PDFKit

/// Was sich mit PDFs anstellen lässt, ohne sie zu öffnen.
///
/// Jede Funktion baut ein **neues** Dokument und lässt das alte, wie es ist.
/// Das ist der Unterschied zwischen einem Werkzeug, das man ausprobiert, und
/// einem, bei dem man vorher eine Kopie anlegt.
public enum PDFTools {
    // MARK: - Zusammenführen

    /// Hängt mehrere Dokumente aneinander.
    public static func merge(_ documents: [PDFDocument]) throws -> PDFDocument {
        let merged = PDFDocument()
        var index = 0
        for document in documents {
            for page in 0..<document.pageCount {
                guard let source = document.page(at: page),
                      let copy = source.copy() as? PDFPage
                else { continue }
                merged.insert(copy, at: index)
                index += 1
            }
        }
        guard merged.pageCount > 0 else {
            throw AnvilError.invalidInput(localized("Keine der Dateien hat eine Seite."))
        }
        return merged
    }

    /// Liest die Dokumente hinter den Adressen.
    ///
    /// Was sich nicht öffnen lässt, fällt heraus und wird gemeldet — der Rest
    /// wird trotzdem verarbeitet. Ein Stapel, der an einer kaputten Datei
    /// ganz abbricht, ist bei zwanzig Dateien unbrauchbar.
    public static func load(_ urls: [URL]) -> (documents: [PDFDocument], failed: [URL]) {
        var documents: [PDFDocument] = []
        var failed: [URL] = []
        for url in urls {
            if let document = PDFDocument(url: url) {
                documents.append(document)
            } else {
                failed.append(url)
            }
        }
        return (documents, failed)
    }

    // MARK: - Auswählen und teilen

    /// Ein neues Dokument aus den gewählten Seiten, in der gewählten
    /// Reihenfolge.
    public static func select(_ range: PageRange, from document: PDFDocument) throws -> PDFDocument {
        guard !range.isEmpty else {
            throw AnvilError.invalidInput(localized("Es ist keine Seite ausgewählt."))
        }
        let result = PDFDocument()
        var index = 0
        for page in range.indices {
            guard let source = document.page(at: page),
                  let copy = source.copy() as? PDFPage
            else { continue }
            result.insert(copy, at: index)
            index += 1
        }
        return result
    }

    /// Alles außer den gewählten Seiten.
    public static func removing(_ range: PageRange, from document: PDFDocument) throws -> PDFDocument {
        let kept = (0..<document.pageCount).filter { !range.indices.contains($0) }
        guard !kept.isEmpty else {
            throw AnvilError.invalidInput(localized("So bliebe keine Seite übrig."))
        }
        return try select(PageRange(pages: kept.map { $0 + 1 }, pageCount: document.pageCount), from: document)
    }

    /// Zerlegt in Teile zu je `size` Seiten.
    public static func split(_ document: PDFDocument, every size: Int) throws -> [PDFDocument] {
        guard size >= 1 else {
            throw AnvilError.invalidInput(localized("Ein Teil hat mindestens eine Seite."))
        }
        guard document.pageCount > 0 else { return [] }

        var parts: [PDFDocument] = []
        var start = 0
        while start < document.pageCount {
            let end = min(start + size, document.pageCount)
            let pages = (start..<end).map { $0 + 1 }
            parts.append(
                try select(PageRange(pages: pages, pageCount: document.pageCount), from: document)
            )
            start = end
        }
        return parts
    }

    // MARK: - Drehen

    /// Dreht die gewählten Seiten.
    ///
    /// PDFKit erwartet ein Vielfaches von 90 und rechnet nicht selbst um —
    /// deshalb wird hier auf 0, 90, 180 oder 270 normalisiert, statt eine
    /// krumme Zahl durchzureichen und sich zu wundern.
    public static func rotated(
        _ document: PDFDocument,
        by degrees: Int,
        pages range: PageRange
    ) throws -> PDFDocument {
        guard document.pageCount > 0 else {
            throw AnvilError.invalidInput(localized("Das Dokument hat keine Seite."))
        }
        let step = normalised(degrees)
        let all = PageRange(pages: Array(1...document.pageCount), pageCount: document.pageCount)
        let result = try select(all, from: document)
        for index in range.indices where index < result.pageCount {
            guard let page = result.page(at: index) else { continue }
            page.rotation = normalised(page.rotation + step)
        }
        return result
    }

    /// Auf 0, 90, 180 oder 270 — auch bei negativen Winkeln.
    static func normalised(_ degrees: Int) -> Int {
        let quarters = Int((Double(degrees) / 90).rounded())
        return ((quarters % 4) + 4) % 4 * 90
    }

    // MARK: - Text

    /// Der Text des Dokuments, Seite für Seite.
    ///
    /// Ein PDF ohne Textschicht — ein Scan — gibt nichts zurück. Das ist kein
    /// Fehler, sondern die Auskunft, dass hier die Texterkennung gebraucht
    /// wird und nicht dieses Werkzeug.
    public static func text(of document: PDFDocument, separator: String = "\n\n") -> String {
        (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: separator)
    }

    // MARK: - Was drinsteht

    public struct Info: Sendable, Hashable {
        public let pageCount: Int
        public let title: String
        public let author: String
        /// Die Größe der ersten Seite in Punkten, gerundet.
        public let width: Int
        public let height: Int
        public let isEncrypted: Bool
        public let hasText: Bool
    }

    public static func info(of document: PDFDocument) -> Info {
        let attributes = document.documentAttributes ?? [:]
        let bounds = document.page(at: 0)?.bounds(for: .mediaBox) ?? .zero
        return Info(
            pageCount: document.pageCount,
            title: attributes[PDFDocumentAttribute.titleAttribute] as? String ?? "",
            author: attributes[PDFDocumentAttribute.authorAttribute] as? String ?? "",
            width: Int(bounds.width.rounded()),
            height: Int(bounds.height.rounded()),
            isEncrypted: document.isEncrypted,
            hasText: !text(of: document).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    // MARK: - Schreiben

    /// Schreibt ein Dokument an eine Adresse.
    public static func write(_ document: PDFDocument, to url: URL) throws {
        guard document.write(to: url) else {
            throw AnvilError.storage(
                localized("Konnte nicht schreiben: \(url.lastPathComponent)")
            )
        }
    }
}
