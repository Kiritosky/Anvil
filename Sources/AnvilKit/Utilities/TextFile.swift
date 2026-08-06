import Foundation

/// Eine Textdatei einlesen, ohne dass die Kodierung zum Glücksspiel wird.
///
/// `String(contentsOf:)` rät die Kodierung und wirft, wenn es danebenliegt —
/// bei allem, was nicht UTF-8 ist, also regelmäßig. Ein Werkzeug, in das man
/// eine Datei zieht, darf daran nicht scheitern: die Datei ist da, sie enthält
/// Text, und die Kodierung ist das Problem des Programms, nicht des Benutzers.
public enum TextFile {
    /// Ab hier ist es keine Textdatei mehr, die jemand von Hand bearbeitet.
    ///
    /// Die Grenze ist großzügig — ein Log mit hunderttausend Zeilen passt
    /// hinein — und existiert, damit ein versehentlich gezogenes Disk-Image
    /// nicht den ganzen Arbeitsspeicher belegt.
    public static let sizeLimit = 16 * 1024 * 1024

    /// Die Kodierungen in der Reihenfolge, in der sie realistisch vorkommen.
    ///
    /// UTF-8 zuerst, dann die beiden, die auf einem Mac aus alten Dateien
    /// kommen. `isoLatin1` steht bewusst am Ende: es akzeptiert jedes
    /// Byte-Muster und würde alles davor unbrauchbar machen.
    ///
    /// UTF-16 fehlt hier mit Absicht. Ohne Byte Order Mark nimmt es jede Datei
    /// mit gerader Länge an und liefert Unsinn — und mit Mark ist es ohnehin
    /// schon vorher erkannt.
    private static let encodings: [String.Encoding] = [
        .utf8, .macOSRoman, .windowsCP1252, .isoLatin1
    ]

    /// Liest die Datei als Text.
    public static func read(at url: URL) throws -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        if let size = attributes?[.size] as? Int, size > sizeLimit {
            throw AnvilError.invalidInput(
                localized("Die Datei ist größer als \(sizeLimit / 1_048_576) MB — das ist kein Text mehr, den man bearbeitet.")
            )
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AnvilError.storage(
                localized("„\(url.lastPathComponent)\" ließ sich nicht lesen: \(error.localizedDescription)")
            )
        }

        guard let text = decode(data) else {
            throw AnvilError.invalidInput(
                localized("„\(url.lastPathComponent)\" enthält keinen lesbaren Text.")
            )
        }
        return text
    }

    /// Macht aus Bytes Text — oder gibt zu, dass es keiner ist.
    ///
    /// Getrennt von ``read(at:)``, weil hier die eigentliche Entscheidung
    /// steckt und sie ohne Dateisystem geprüft werden kann.
    public static func decode(_ data: Data) -> String? {
        guard !data.isEmpty else { return "" }

        // Eine Byte Order Mark ist die einzige Stelle, an der eine Datei ihre
        // Kodierung selbst angibt. Wer sie ignoriert, liest UTF-16 als Latin-1
        // und bekommt Text mit einem Nullbyte zwischen jedem Buchstaben.
        if let fromMark = decodeUsingByteOrderMark(data) { return fromMark }

        // Nullbytes im vorderen Teil heißen: das ist binär. Ohne diese Prüfung
        // liefert isoLatin1 für ein PNG bereitwillig „Text" aus Kästchen.
        if data.prefix(4096).contains(0) { return nil }

        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return nil
    }

    private static func decodeUsingByteOrderMark(_ data: Data) -> String? {
        let marks: [(bytes: [UInt8], encoding: String.Encoding)] = [
            ([0xEF, 0xBB, 0xBF], .utf8),
            ([0xFF, 0xFE], .utf16LittleEndian),
            ([0xFE, 0xFF], .utf16BigEndian)
        ]

        for mark in marks where data.starts(with: mark.bytes) {
            let body = data.dropFirst(mark.bytes.count)
            return String(data: body, encoding: mark.encoding)
        }
        return nil
    }
}
