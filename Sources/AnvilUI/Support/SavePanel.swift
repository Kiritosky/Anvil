import AnvilKit
import AppKit
import Foundation
import UniformTypeIdentifiers

/// „Sichern unter" — einmal für alle Werkzeuge.
///
/// Text lässt sich nicht sinnvoll herausziehen: dieselbe Fläche trägt schon
/// die Textauswahl, und zwei Gesten auf einer Fläche heißt, dass keine von
/// beiden zuverlässig auslöst. Für Text ist der Dialog also nicht die
/// zweitbeste Lösung, sondern die richtige.
@MainActor
public enum SavePanel {
    /// Fragt nach einem Ort und schreibt den Text dorthin.
    ///
    /// Gibt zurück, wo die Datei liegt — oder `nil`, wenn abgebrochen wurde.
    /// Abbrechen ist kein Fehler und darf deshalb auch keinen erzeugen.
    @discardableResult
    public static func write(
        _ text: String,
        suggestedName: String,
        type: UTType = .plainText
    ) throws -> URL? {
        guard let url = ask(suggestedName: suggestedName, type: type) else { return nil }

        do {
            try Data(text.utf8).write(to: url)
        } catch {
            throw AnvilError.storage(
                localized("Sichern nach „\(url.lastPathComponent)\" ist fehlgeschlagen: \(error.localizedDescription)")
            )
        }
        return url
    }

    /// Dasselbe für ein Bild, immer als PNG.
    @discardableResult
    public static func write(_ image: NSImage, suggestedName: String) throws -> URL? {
        guard let url = ask(suggestedName: suggestedName, type: .png) else { return nil }
        return try image.writePNG(to: url)
    }

    /// Fragt nur nach dem Ort und schreibt selbst nichts.
    ///
    /// Für alles, was schon als fertige Bytes vorliegt — ein umgewandeltes
    /// Bild etwa. Die Alternative wäre, die Daten durch eine der
    /// `write`-Methoden zu schleusen, die sie vorher gar nicht kennt.
    public static func url(suggestedName: String, type: UTType) -> URL? {
        ask(suggestedName: suggestedName, type: type)
    }

    private static func ask(suggestedName: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = ExportFile.sanitize(suggestedName)
        panel.canCreateDirectories = true
        // Ohne das steht der Dialog hinter dem Fenster, wenn Anvil gerade
        // nicht die vorderste App ist — etwa direkt nach einem Kürzel.
        panel.level = .modalPanel

        return panel.runModal() == .OK ? panel.url : nil
    }
}
