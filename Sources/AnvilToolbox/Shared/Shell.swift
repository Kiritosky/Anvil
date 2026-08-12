import Foundation

/// Text, den man in ein Terminal einfügen kann.
///
/// Anvil führt keine dieser Zeilen aus — es baut sie und legt sie in die
/// Zwischenablage. Der Unterschied ist nicht Bequemlichkeit, sondern
/// Verantwortung: Ein Befehl, der Zweige oder Dateien entfernt, gehört dorthin,
/// wo man sieht, was passiert, und wo man ihn vorher lesen kann.
enum Shell {
    /// Ein Argument, das die Shell unverändert durchreicht.
    ///
    /// Einfache Anführungszeichen schützen alles außer sich selbst; ein eigenes
    /// davon wird beendet, als Literal eingefügt und wieder aufgemacht. Ein
    /// Ordner namens `Annas' Projekte` ist selten, aber der Befehl, der daran
    /// zerbricht, wäre eine böse Überraschung.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
