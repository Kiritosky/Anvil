import Foundation

/// Aus beliebigem Text eine Kurzform, die als Adresse, Dateiname oder Kennung
/// durchgeht.
///
/// Lag vorher im Textkatalog und liegt jetzt hier, weil ein zweites Werkzeug
/// dasselbe braucht: Wer sich ein eigenes Werkzeug baut, gibt ihm einen Titel,
/// und daraus muss eine Kennung werden.
enum Slug {
    static func make(_ input: String, separator: String = "-") -> String {
        // Umlaute werden zu zwei Buchstaben und nicht zu einem. Das ist die
        // deutsche Schreibweise und zugleich die einzig richtige: Foundations
        // Diakritika-Faltung macht aus „Größe" ein „grosse" und trifft damit
        // auf das andere Wort „Grosse". Also erst umschreiben, dann falten —
        // Akzente aus anderen Sprachen wollen tatsächlich den nackten
        // Buchstaben.
        var transliterated = input
        for (umlaut, replacement) in umlautTransliterations {
            transliterated = transliterated.replacingOccurrences(of: umlaut, with: replacement)
        }

        let folded = transliterated
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let parts = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(parts)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: separator)
            .lowercased()
    }

    static let umlautTransliterations: [(String, String)] = [
        ("ä", "ae"), ("ö", "oe"), ("ü", "ue"),
        ("Ä", "Ae"), ("Ö", "Oe"), ("Ü", "Ue"),
        ("ß", "ss")
    ]
}
