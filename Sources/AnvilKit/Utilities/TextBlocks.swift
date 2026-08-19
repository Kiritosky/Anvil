import Foundation

/// Text aus mehreren Quellen zu einem Dokument zusammensetzen.
public enum TextBlocks {
    /// Fügt benannte Textstücke zusammen.
    public static func combine(
        _ pieces: [(name: String, text: String)],
        emptyNote: String = localized("— kein Text —")
    ) -> String {
        guard pieces.count != 1 else { return pieces[0].text }

        return pieces
            .map { piece in
                let body = piece.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return body.isEmpty
                    ? "\(piece.name)\n\(emptyNote)"
                    : "\(piece.name)\n\(body)"
            }
            .joined(separator: "\n\n")
    }
}
