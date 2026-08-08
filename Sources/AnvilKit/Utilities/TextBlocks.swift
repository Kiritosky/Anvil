import Foundation

/// Text aus mehreren Quellen zu einem Dokument zusammensetzen.
///
/// Der Fall kommt in der App zweimal vor und wird noch öfter vorkommen: Text
/// aus mehreren Bildern, Transkripte mehrerer Aufnahmen. Beide Male stellt
/// sich dieselbe Frage, und beide Male ist die Antwort dieselbe — also steht
/// sie einmal hier statt zweimal irgendwo.
public enum TextBlocks {
    /// Fügt benannte Textstücke zusammen.
    ///
    /// Bei einem Stück bleibt es der reine Text: Man will ihn einfügen, nicht
    /// lesen, wo er herkommt. Ab zwei bekommt jeder Block seinen Namen davor,
    /// denn ohne den weiß nach dem Einfügen niemand mehr, welcher Absatz aus
    /// welcher Quelle stammt — und das ist genau der Fall, für den man
    /// mehrere auf einmal verarbeitet.
    ///
    /// Leere Stücke fallen nicht heraus, sondern bekommen ihren Hinweis. Eine
    /// Lücke, die man nicht sieht, hält man für Inhalt, den es nie gab.
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
