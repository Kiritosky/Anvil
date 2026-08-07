import Foundation

/// Dateien, die es nur gibt, weil etwas den Rechner verlässt.
///
/// Wer ein Ergebnis in den Finder zieht, erwartet dort eine Datei mit einem
/// vernünftigen Namen — und nicht, dass Anvil ihm dafür vorher einen
/// Speicherort abringt. Also entsteht die Datei im temporären Verzeichnis, und
/// wo sie am Ende landet, entscheidet das Ziel des Zugs.
public enum ExportFile {
    /// Aus einem beliebigen Text ein Dateiname, den das Dateisystem annimmt.
    ///
    /// Der Name kommt aus Inhalten — der ersten Zeile eines Ergebnisses, dem
    /// Text hinter einem QR-Code — und darf deshalb alles enthalten:
    /// Schrägstriche, Zeilenumbrüche, tausend Zeichen, oder gar nichts.
    public static func sanitize(_ name: String, fallback: String = "Anvil") -> String {
        // Der Schrägstrich trennt auf Unix-Ebene Pfade, der Doppelpunkt tut es
        // im Finder. Steuerzeichen sind erlaubt, ergeben aber Namen, die man
        // im Terminal nicht mehr tippen kann.
        let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)

        let collapsed = name
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // Ein Name, der mit einem Punkt beginnt, ist auf dem Mac unsichtbar —
        // eine unsichtbare Datei auf dem Schreibtisch ist keine Hilfe.
        var trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if trimmed.count > 80 {
            trimmed = String(trimmed.prefix(80)).trimmingCharacters(in: .whitespaces)
        }
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// Legt eine Datei zum Herausziehen an und gibt zurück, wo sie liegt.
    ///
    /// Jeder Export bekommt einen eigenen Unterordner. Ohne den würde ein
    /// zweiter Zug mit demselben Namen den ersten überschreiben — während der
    /// erste vielleicht noch kopiert wird.
    public static func temporary(
        named name: String,
        extension pathExtension: String,
        contents: Data
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Anvil-Export/\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = directory.appending(path: "\(sanitize(name)).\(pathExtension)")
            try contents.write(to: url)
            return url
        } catch {
            throw AnvilError.storage(
                localized("Die Datei zum Herausziehen ließ sich nicht anlegen: \(error.localizedDescription)")
            )
        }
    }
}
