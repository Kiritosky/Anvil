import Foundation

/// Text in Zeilen zerlegen, egal von welchem System er kommt.
public enum TextLines {
    /// Alle Zeilenenden zu `\n`.
    public static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Die Zeilen des Textes.
    public static func split(_ text: String, keepingEmpty: Bool = true) -> [String] {
        let lines = normalized(text).components(separatedBy: "\n")
        return keepingEmpty ? lines : lines.filter { !$0.isEmpty }
    }

    /// Wie viele Zeilen der Text hat.
    public static func count(_ text: String) -> Int {
        text.isEmpty ? 0 : split(text).count
    }
}
