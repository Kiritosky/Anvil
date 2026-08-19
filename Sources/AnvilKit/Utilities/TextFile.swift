import Foundation

/// Eine Textdatei einlesen, ohne dass die Kodierung zum Glücksspiel wird.
public enum TextFile {
    /// Ab hier ist es keine Textdatei mehr, die jemand von Hand bearbeitet.
    public static let sizeLimit = 16 * 1024 * 1024

    /// Die Kodierungen in der Reihenfolge, in der sie probiert werden.
    private static let encodings: [String.Encoding] = [
        .utf8, .windowsCP1252, .isoLatin1
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
    public static func decode(_ data: Data) -> String? {
        guard !data.isEmpty else { return "" }

        if let fromMark = decodeUsingByteOrderMark(data) { return fromMark }

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
