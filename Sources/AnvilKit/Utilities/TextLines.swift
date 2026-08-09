import Foundation

/// Text in Zeilen zerlegen, egal von welchem System er kommt.
///
/// Es gibt dafür einen eigenen Typ, weil beide naheliegenden Abkürzungen
/// falsch sind:
///
/// - `text.split(separator: "\n")` trennt **gar nicht** bei
///   Windows-Zeilenenden. `"\r\n"` ist in Swift ein einziger `Character` —
///   eine Datei aus Excel käme als eine einzige Zeile heraus.
/// - `text.components(separatedBy: .newlines)` trennt an Unicode-*Skalaren*
///   und macht aus jedem `"\r\n"` zwei Trennungen, also eine Leerzeile, die
///   es nicht gibt. Jede Zählung darüber ist danach zu hoch.
///
/// Deshalb wird erst vereinheitlicht und dann getrennt.
public enum TextLines {
    /// Alle Zeilenenden zu `\n`.
    ///
    /// Erst CRLF, dann das einzelne CR — andersherum würde aus jedem CRLF ein
    /// doppelter Umbruch.
    public static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Die Zeilen des Textes.
    ///
    /// Leerzeilen bleiben standardmäßig erhalten: wer Zeilen zählt oder
    /// Zeilennummern vergibt, braucht sie.
    public static func split(_ text: String, keepingEmpty: Bool = true) -> [String] {
        let lines = normalized(text).components(separatedBy: "\n")
        return keepingEmpty ? lines : lines.filter { !$0.isEmpty }
    }

    /// Wie viele Zeilen der Text hat.
    ///
    /// Leerer Text hat null Zeilen und nicht eine — `components` gäbe hier
    /// sonst `[""]` zurück und damit die Zahl 1 für gar nichts.
    public static func count(_ text: String) -> Int {
        text.isEmpty ? 0 : split(text).count
    }
}
