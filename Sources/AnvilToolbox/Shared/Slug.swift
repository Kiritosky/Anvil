import Foundation

/// Aus beliebigem Text eine Kurzform, die als Adresse, Dateiname oder Kennung
/// durchgeht.
enum Slug {
    static func make(_ input: String, separator: String = "-") -> String {
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
