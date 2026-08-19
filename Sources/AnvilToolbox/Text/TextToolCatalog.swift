import AnvilKit
import CryptoKit
import Foundation

/// The deterministic tools Anvil ships with.
public enum TextToolCatalog {
    public static var all: [TextTool] {
        [json, base64, urlCoding, jwt, hashes, uuid, timestamps, caseConversion, lines, slug, hex, htmlEntities, statistics]
    }

    // MARK: - JSON

    static var json: TextTool {
        TextTool(
            id: "text.json",
            title: "JSON",
            subtitle: "Formatieren, verkleinern, prüfen",
            systemImage: "curlybraces",
            category: .coding,
            keywords: ["json", "format", "pretty", "minify", "validieren", "parser"],
            placeholder: "{ \"hallo\": \"welt\" }",
            modes: [
                TextToolMode(id: "pretty", title: "Formatieren", systemImage: "text.alignleft") { input in
                    let object = try parseJSON(input)
                    return try serialiseJSON(object, options: [.prettyPrinted, .fragmentsAllowed])
                },
                TextToolMode(id: "sorted", title: "Formatiert + sortiert", systemImage: "arrow.up.arrow.down") { input in
                    let object = try parseJSON(input)
                    return try serialiseJSON(object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
                },
                TextToolMode(id: "minify", title: "Verkleinern", systemImage: "arrow.down.right.and.arrow.up.left") { input in
                    let object = try parseJSON(input)
                    return try serialiseJSON(object, options: [.fragmentsAllowed])
                },
                TextToolMode(id: "validate", title: "Nur prüfen", systemImage: "checkmark.seal") { input in
                    let object = try parseJSON(input)
                    return describeJSON(object)
                },
                TextToolMode(id: "escape", title: "Als String escapen", systemImage: "quote.opening") { input in
                    let data = try JSONSerialization.data(withJSONObject: [input], options: [])
                    let wrapped = String(decoding: data, as: UTF8.self)
                    return String(wrapped.dropFirst().dropLast())
                }
            ]
        )
    }

    // MARK: - Base64

    static var base64: TextTool {
        TextTool(
            id: "text.base64",
            title: "Base64",
            subtitle: "Kodieren und dekodieren",
            systemImage: "arrow.left.arrow.right.square",
            category: .coding,
            keywords: ["base64", "encode", "decode", "kodieren", "dekodieren"],
            handlesSecrets: true,
            modes: [
                TextToolMode(id: "encode", title: "Kodieren", systemImage: "lock") { input in
                    Data(input.utf8).base64EncodedString()
                },
                TextToolMode(id: "decode", title: "Dekodieren", systemImage: "lock.open") { input in
                    guard let data = Data(base64Encoded: paddedBase64(input)) else {
                        throw AnvilError.invalidInput(localized("Das ist kein gültiges Base64."))
                    }
                    return String(decoding: data, as: UTF8.self)
                },
                TextToolMode(id: "encodeURL", title: "URL-sicher kodieren", systemImage: "link") { input in
                    Data(input.utf8).base64EncodedString()
                        .replacingOccurrences(of: "+", with: "-")
                        .replacingOccurrences(of: "/", with: "_")
                        .replacingOccurrences(of: "=", with: "")
                }
            ]
        )
    }

    // MARK: - URL

    static var urlCoding: TextTool {
        TextTool(
            id: "text.url",
            title: "URL",
            subtitle: "Escapen, entpacken, Parameter lesen",
            systemImage: "link",
            category: .coding,
            keywords: ["url", "percent", "encode", "decode", "query", "parameter"],
            modes: [
                TextToolMode(id: "encode", title: "Kodieren", systemImage: "lock") { input in
                    guard let encoded = input.addingPercentEncoding(
                        withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))
                    ) else {
                        throw AnvilError.invalidInput(localized("Der Text lässt sich nicht kodieren."))
                    }
                    return encoded
                },
                TextToolMode(id: "decode", title: "Dekodieren", systemImage: "lock.open") { input in
                    guard let decoded = input.removingPercentEncoding else {
                        throw AnvilError.invalidInput(localized("Das ist keine gültige prozentkodierte Zeichenkette."))
                    }
                    return decoded
                },
                TextToolMode(id: "query", title: "Parameter auflisten", systemImage: "list.bullet") { input in
                    guard let components = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines))
                    else {
                        throw AnvilError.invalidInput(localized("Das ist keine gültige URL."))
                    }
                    let items = components.queryItems ?? []
                    guard !items.isEmpty else { return "Keine Query-Parameter." }

                    let width = items.map(\.name.count).max() ?? 0
                    return items
                        .map { "\($0.name.padding(toLength: width, withPad: " ", startingAt: 0))  \($0.value ?? "")" }
                        .joined(separator: "\n")
                }
            ]
        )
    }

    // MARK: - JWT

    static var jwt: TextTool {
        TextTool(
            id: "text.jwt",
            title: "JWT",
            subtitle: "Token lesbar machen",
            systemImage: "key",
            category: .coding,
            keywords: ["jwt", "token", "jose", "claims", "auth"],
            placeholder: "eyJhbGciOi…",
            handlesSecrets: true,
            modes: [
                TextToolMode(id: "decode", title: "Dekodieren", systemImage: "eye") { input in
                    let parts = input.trimmingCharacters(in: .whitespacesAndNewlines)
                        .split(separator: ".", omittingEmptySubsequences: false)
                    guard parts.count >= 2 else {
                        throw AnvilError.invalidInput(localized("Ein JWT besteht aus drei mit Punkt getrennten Teilen."))
                    }

                    let header = try decodeJWTSegment(String(parts[0]), label: "Header")
                    let payload = try decodeJWTSegment(String(parts[1]), label: "Payload")

                    var result = "// Header\n\(header)\n\n// Payload\n\(payload)"
                    if let expiry = expiryDescription(from: parts.count > 1 ? String(parts[1]) : "") {
                        result += "\n\n// \(expiry)"
                    }
                    return result
                }
            ]
        )
    }

    // MARK: - Hashes

    static var hashes: TextTool {
        TextTool(
            id: "text.hash",
            title: "Prüfsummen",
            subtitle: "MD5, SHA-1, SHA-256, SHA-512 — auch von Dateien",
            systemImage: "number",
            category: .coding,
            keywords: [
                "hash", "md5", "sha", "checksum", "prüfsumme", "digest",
                "datei", "download", "verifizieren", "integrität"
            ],
            handlesSecrets: true,
            modes: [
                TextToolMode(
                    id: "sha256",
                    title: "SHA-256",
                    runOnFiles: { try FileDigest.report(SHA256.self, of: $0) }
                ) { input in
                    hexString(SHA256.hash(data: Data(input.utf8)))
                },
                TextToolMode(
                    id: "sha512",
                    title: "SHA-512",
                    runOnFiles: { try FileDigest.report(SHA512.self, of: $0) }
                ) { input in
                    hexString(SHA512.hash(data: Data(input.utf8)))
                },
                TextToolMode(
                    id: "sha1",
                    title: "SHA-1",
                    runOnFiles: { try FileDigest.report(Insecure.SHA1.self, of: $0) }
                ) { input in
                    hexString(Insecure.SHA1.hash(data: Data(input.utf8)))
                },
                TextToolMode(
                    id: "md5",
                    title: "MD5",
                    runOnFiles: { try FileDigest.report(Insecure.MD5.self, of: $0) }
                ) { input in
                    hexString(Insecure.MD5.hash(data: Data(input.utf8)))
                },
                TextToolMode(
                    id: "all",
                    title: "Alle",
                    systemImage: "list.bullet",
                    runOnFiles: { FileDigest.allLines(of: $0) }
                ) { input in
                    let data = Data(input.utf8)
                    return """
                    MD5      \(hexString(Insecure.MD5.hash(data: data)))
                    SHA-1    \(hexString(Insecure.SHA1.hash(data: data)))
                    SHA-256  \(hexString(SHA256.hash(data: data)))
                    SHA-512  \(hexString(SHA512.hash(data: data)))
                    """
                }
            ]
        )
    }

    // MARK: - UUID

    static var uuid: TextTool {
        TextTool(
            id: "text.uuid",
            title: "UUID",
            subtitle: "Kennungen erzeugen",
            systemImage: "number.square",
            category: .coding,
            keywords: ["uuid", "guid", "id", "erzeugen", "generate"],
            placeholder: "Braucht keine Eingabe.",
            generatesWithoutInput: true,
            modes: [
                TextToolMode(id: "one", title: "Eine") { _ in UUID().uuidString },
                TextToolMode(id: "ten", title: "Zehn") { _ in
                    (0..<10).map { _ in UUID().uuidString }.joined(separator: "\n")
                },
                TextToolMode(id: "lower", title: "Klein geschrieben") { _ in
                    UUID().uuidString.lowercased()
                },
                TextToolMode(id: "compact", title: "Ohne Bindestriche") { _ in
                    UUID().uuidString.replacingOccurrences(of: "-", with: "")
                }
            ]
        )
    }

    // MARK: - Timestamps

    static var timestamps: TextTool {
        TextTool(
            id: "text.timestamp",
            title: "Zeitstempel",
            subtitle: "Unix-Zeit und ISO 8601 umrechnen",
            systemImage: "clock",
            category: .coding,
            keywords: ["timestamp", "unix", "epoch", "iso8601", "datum", "zeit"],
            placeholder: "1735689600 oder 2025-01-01T00:00:00Z",
            generatesWithoutInput: true,
            modes: [
                TextToolMode(id: "auto", title: "Erkennen", systemImage: "wand.and.stars") { input in
                    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return describeDate(.now) }

                    if let seconds = Double(trimmed) {
                        let date = Date(timeIntervalSince1970: seconds > 100_000_000_000 ? seconds / 1000 : seconds)
                        return describeDate(date)
                    }
                    guard let date = parseDate(trimmed) else {
                        throw AnvilError.invalidInput(localized("Weder Unix-Zeit noch ein erkennbares Datum."))
                    }
                    return describeDate(date)
                },
                TextToolMode(id: "now", title: "Jetzt", systemImage: "clock.badge") { _ in
                    describeDate(.now)
                }
            ]
        )
    }

    // MARK: - Case

    static var caseConversion: TextTool {
        TextTool(
            id: "text.case",
            title: "Schreibweise",
            subtitle: "camelCase, snake_case, kebab-case …",
            systemImage: "textformat",
            category: .coding,
            keywords: ["case", "camel", "snake", "kebab", "pascal", "schreibweise", "benennung"],
            isMonospaced: false,
            modes: [
                TextToolMode(id: "camel", title: "camelCase") { joinWords($0) { index, word in
                    index == 0 ? word.lowercased() : word.capitalized
                } },
                TextToolMode(id: "pascal", title: "PascalCase") { joinWords($0) { _, word in word.capitalized } },
                TextToolMode(id: "snake", title: "snake_case") { words($0).map { $0.lowercased() }.joined(separator: "_") },
                TextToolMode(id: "kebab", title: "kebab-case") { words($0).map { $0.lowercased() }.joined(separator: "-") },
                TextToolMode(id: "constant", title: "CONSTANT_CASE") { words($0).map { $0.uppercased() }.joined(separator: "_") },
                TextToolMode(id: "title", title: "Titel") { words($0).map { $0.capitalized }.joined(separator: " ") },
                TextToolMode(id: "upper", title: "GROSS") { $0.uppercased() },
                TextToolMode(id: "lower", title: "klein") { $0.lowercased() }
            ]
        )
    }

    // MARK: - Lines

    static var lines: TextTool {
        TextTool(
            id: "text.lines",
            title: "Zeilen",
            subtitle: "Sortieren, entdoppeln, nummerieren",
            systemImage: "list.number",
            category: .text,
            keywords: ["zeilen", "sortieren", "unique", "duplikate", "liste"],
            isMonospaced: false,
            modes: [
                TextToolMode(id: "sort", title: "A → Z") { splitLines($0).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n") },
                TextToolMode(id: "sortDesc", title: "Z → A") { splitLines($0).sorted { $0.localizedStandardCompare($1) == .orderedDescending }.joined(separator: "\n") },
                TextToolMode(id: "unique", title: "Doppelte entfernen") { input in
                    var seen = Set<String>()
                    return splitLines(input).filter { seen.insert($0).inserted }.joined(separator: "\n")
                },
                TextToolMode(id: "reverse", title: "Umdrehen") { splitLines($0).reversed().joined(separator: "\n") },
                TextToolMode(id: "trim", title: "Ränder trimmen") { splitLines($0).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n") },
                TextToolMode(id: "compact", title: "Leerzeilen weg") { splitLines($0).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n") },
                TextToolMode(id: "number", title: "Nummerieren") { input in
                    splitLines(input).enumerated()
                        .map { "\($0.offset + 1). \($0.element)" }
                        .joined(separator: "\n")
                },
                TextToolMode(id: "join", title: "Zu einer Zeile") { splitLines($0).joined(separator: ", ") }
            ]
        )
    }

    // MARK: - Slug

    static var slug: TextTool {
        TextTool(
            id: "text.slug",
            title: "Slug",
            subtitle: "URL-taugliche Kurzform",
            systemImage: "link.badge.plus",
            category: .text,
            keywords: ["slug", "url", "permalink", "dateiname"],
            isMonospaced: false,
            modes: [
                TextToolMode(id: "kebab", title: "mit-bindestrichen") { Slug.make($0, separator: "-") },
                TextToolMode(id: "snake", title: "mit_unterstrichen") { Slug.make($0, separator: "_") }
            ]
        )
    }

    // MARK: - Hex

    static var hex: TextTool {
        TextTool(
            id: "text.hex",
            title: "Hex",
            subtitle: "Text und Hexadezimal",
            systemImage: "number.circle",
            category: .coding,
            keywords: ["hex", "hexadezimal", "bytes", "dump"],
            handlesSecrets: true,
            modes: [
                TextToolMode(id: "encode", title: "Nach Hex") { input in
                    Data(input.utf8).map { String(format: "%02x", $0) }.joined(separator: " ")
                },
                TextToolMode(id: "decode", title: "Von Hex") { input in
                    let cleaned = input.replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: "\n", with: "")
                        .replacingOccurrences(of: "0x", with: "")
                    guard cleaned.count.isMultiple(of: 2) else {
                        throw AnvilError.invalidInput(localized("Hex braucht eine gerade Anzahl Zeichen."))
                    }
                    var bytes = [UInt8]()
                    var index = cleaned.startIndex
                    while index < cleaned.endIndex {
                        let next = cleaned.index(index, offsetBy: 2)
                        guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
                            throw AnvilError.invalidInput(localized("„\(cleaned[index..<next])\" ist kein Hex-Byte."))
                        }
                        bytes.append(byte)
                        index = next
                    }
                    return String(decoding: Data(bytes), as: UTF8.self)
                }
            ]
        )
    }

    // MARK: - HTML

    static var htmlEntities: TextTool {
        TextTool(
            id: "text.html",
            title: "HTML-Entities",
            subtitle: "Sonderzeichen escapen",
            systemImage: "chevron.left.slash.chevron.right",
            category: .coding,
            keywords: ["html", "xml", "escape", "entities", "sonderzeichen"],
            modes: [
                TextToolMode(id: "escape", title: "Escapen") { input in
                    input
                        .replacingOccurrences(of: "&", with: "&amp;")
                        .replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: ">", with: "&gt;")
                        .replacingOccurrences(of: "\"", with: "&quot;")
                        .replacingOccurrences(of: "'", with: "&#39;")
                },
                TextToolMode(id: "unescape", title: "Zurückwandeln") { input in
                    input
                        .replacingOccurrences(of: "&lt;", with: "<")
                        .replacingOccurrences(of: "&gt;", with: ">")
                        .replacingOccurrences(of: "&quot;", with: "\"")
                        .replacingOccurrences(of: "&#39;", with: "'")
                        .replacingOccurrences(of: "&nbsp;", with: " ")
                        .replacingOccurrences(of: "&amp;", with: "&")
                }
            ]
        )
    }

    // MARK: - Statistics

    static var statistics: TextTool {
        TextTool(
            id: "text.stats",
            title: "Textstatistik",
            subtitle: "Wörter, Zeichen, Lesezeit",
            systemImage: "chart.bar",
            category: .text,
            keywords: ["statistik", "wörter", "zeichen", "lesezeit", "zählen"],
            isMonospaced: false,
            modes: [
                TextToolMode(id: "stats", title: "Auswerten") { input in
                    let words = input.split(whereSeparator: \.isWhitespace)
                    let lineCount = TextLines.count(input)
                    let sentences = input.split(whereSeparator: { ".!?".contains($0) })
                        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    let minutes = max(1, Int((Double(words.count) / 200.0).rounded(.up)))
                    let unique = Set(words.map { $0.lowercased() }).count

                    return """
                    Zeichen            \(input.count)
                    Zeichen ohne Leer  \(input.filter { !$0.isWhitespace }.count)
                    Wörter             \(words.count)
                    Verschiedene       \(unique)
                    Sätze              \(sentences.count)
                    Zeilen             \(lineCount)
                    Lesezeit           ca. \(minutes) min
                    """
                }
            ]
        )
    }

    // MARK: - Helpers

    private static func parseJSON(_ input: String) throws -> Any {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AnvilError.invalidInput(localized("Da ist noch nichts."))
        }
        do {
            return try JSONSerialization.jsonObject(
                with: Data(trimmed.utf8),
                options: [.fragmentsAllowed]
            )
        } catch {
            throw AnvilError.invalidInput(localized("Kein gültiges JSON: \(error.localizedDescription)"))
        }
    }

    private static func serialiseJSON(_ object: Any, options: JSONSerialization.WritingOptions) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: options)
        return String(decoding: data, as: UTF8.self)
    }

    private static func describeJSON(_ object: Any) -> String {
        switch object {
        case let dictionary as [String: Any]:
            "Gültiges JSON-Objekt mit \(dictionary.count) Schlüsseln."
        case let array as [Any]:
            "Gültiges JSON-Array mit \(array.count) Einträgen."
        default:
            "Gültiger JSON-Wert."
        }
    }

    /// Base64 from JWTs and URLs routinely arrives without its padding.
    private static func paddedBase64(_ input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = value.count % 4
        if remainder > 0 { value += String(repeating: "=", count: 4 - remainder) }
        return value
    }

    private static func decodeJWTSegment(_ segment: String, label: String) throws -> String {
        guard let data = Data(base64Encoded: paddedBase64(segment)) else {
            throw AnvilError.invalidInput(localized("Der \(label) ist kein gültiges Base64."))
        }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
              )
        else {
            return String(decoding: data, as: UTF8.self)
        }
        return String(decoding: pretty, as: UTF8.self)
    }

    /// Reads `exp` out of a payload and says whether the token is still valid —
    /// the actual question anyone decoding a JWT by hand is asking.
    private static func expiryDescription(from payloadSegment: String) -> String? {
        guard let data = Data(base64Encoded: paddedBase64(payloadSegment)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? Double
        else { return nil }

        let date = Date(timeIntervalSince1970: exp)
        let formatted = date.formatted(date: .abbreviated, time: .standard)
        return date > .now
            ? "Gültig bis \(formatted)"
            : "Abgelaufen am \(formatted)"
    }

    private static func hexString(_ digest: some Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func splitLines(_ input: String) -> [String] {
        input.components(separatedBy: .newlines)
    }

    /// Splits an identifier or sentence into words, whatever convention it uses.
    private static func words(_ input: String) -> [String] {
        var result: [String] = []
        var current = ""

        for character in input {
            if character.isWhitespace || character == "_" || character == "-" || character == "." {
                if !current.isEmpty { result.append(current); current = "" }
            } else if character.isUppercase, !current.isEmpty, current.last?.isUppercase == false {
                result.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result.filter { !$0.isEmpty }
    }

    private static func joinWords(_ input: String, transform: (Int, String) -> String) -> String {
        words(input).enumerated().map { transform($0.offset, $0.element.lowercased()) }.joined()
    }

    private static func describeDate(_ date: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        return """
        Unix (s)       \(Int(date.timeIntervalSince1970))
        Unix (ms)      \(Int(date.timeIntervalSince1970 * 1000))
        ISO 8601       \(iso.string(from: date))
        Lokal          \(date.formatted(date: .complete, time: .standard))
        Relativ        \(date.formatted(.relative(presentation: .named)))
        """
    }

    private static func parseDate(_ input: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: input) { return date }

        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: input) { return date }

        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "dd.MM.yyyy", "dd.MM.yyyy HH:mm"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: input) { return date }
        }
        return nil
    }
}
