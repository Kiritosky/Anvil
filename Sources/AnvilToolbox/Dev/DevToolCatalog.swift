import AnvilKit
import Foundation

/// Deterministic tools for the other half of the day.
public enum DevToolCatalog {
    public static var all: [TextTool] {
        [numbers, unicode, permissions, statusCodes, cron]
    }

    // MARK: - Number bases

    static var numbers: TextTool {
        TextTool(
            id: "dev.numbers",
            title: "Zahlensysteme",
            subtitle: "Dezimal, Hex, Binär, Oktal",
            systemImage: "number.square",
            category: .coding,
            keywords: [
                "hex", "hexadezimal", "binär", "binary", "oktal", "dezimal",
                "umrechnen", "basis", "base", "0x", "zweierkomplement"
            ],
            placeholder: "255 · 0xFF · 0b1111_1111 · 0o377",
            modes: [
                TextToolMode(id: "all", title: "Alle Systeme", systemImage: "list.bullet") { input in
                    let value = try parseInteger(input)
                    return """
                    Dezimal  \(value)
                    Hex      0x\(String(value, radix: 16).uppercased())
                    Binär    0b\(grouped(String(value, radix: 2), by: 4))
                    Oktal    0o\(String(value, radix: 8))
                    """
                },
                TextToolMode(id: "hex", title: "Nach Hex", systemImage: "number") { input in
                    "0x" + String(try parseInteger(input), radix: 16).uppercased()
                },
                TextToolMode(id: "bin", title: "Nach Binär", systemImage: "01.square") { input in
                    "0b" + grouped(String(try parseInteger(input), radix: 2), by: 4)
                },
                TextToolMode(id: "oct", title: "Nach Oktal", systemImage: "8.square") { input in
                    "0o" + String(try parseInteger(input), radix: 8)
                },
                TextToolMode(id: "dec", title: "Nach Dezimal", systemImage: "textformat.123") { input in
                    String(try parseInteger(input))
                }
            ]
        )
    }

    /// Reads `255`, `0xFF`, `#FF`, `0b1010`, `0o377` — and the same with
    /// underscores or spaces for grouping.
    static func parseInteger(_ input: String) throws -> Int {
        var text = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")

        var sign = 1
        if text.hasPrefix("-") {
            sign = -1
            text.removeFirst()
        }

        let radix: Int
        switch true {
        case text.hasPrefix("0x"), text.hasPrefix("#"):
            radix = 16
            text = String(text.dropFirst(text.hasPrefix("#") ? 1 : 2))
        case text.hasPrefix("0b"):
            radix = 2
            text = String(text.dropFirst(2))
        case text.hasPrefix("0o"):
            radix = 8
            text = String(text.dropFirst(2))
        default:
            radix = 10
        }

        guard !text.isEmpty, let value = Int(text, radix: radix) else {
            throw AnvilError.invalidInput(
                localized("Das ist keine Zahl, die ich lesen kann: „\(input)\".")
            )
        }
        return sign * value
    }

    /// Groups digits from the right, the way binary is read.
    static func grouped(_ digits: String, by size: Int) -> String {
        var result: [String] = []
        var remaining = Substring(digits)
        while remaining.count > size {
            result.append(String(remaining.suffix(size)))
            remaining = remaining.dropLast(size)
        }
        result.append(String(remaining))
        return result.reversed().joined(separator: "_")
    }

    // MARK: - Unicode

    static var unicode: TextTool {
        TextTool(
            id: "dev.unicode",
            title: "Zeichen",
            subtitle: "Code-Points, Namen, UTF-8",
            systemImage: "character.magnify",
            category: .coding,
            keywords: [
                "unicode", "codepoint", "utf8", "utf-8", "zeichen", "emoji",
                "unsichtbar", "geschütztes leerzeichen", "encoding"
            ],
            placeholder: "Text, dessen Zeichen du sehen willst …",
            modes: [
                TextToolMode(id: "breakdown", title: "Aufschlüsseln", systemImage: "list.bullet") { input in
                    try describeCharacters(input, suspiciousOnly: false)
                },
                TextToolMode(id: "suspicious", title: "Nur Auffälliges", systemImage: "eye.trianglebadge.exclamationmark") { input in
                    try describeCharacters(input, suspiciousOnly: true)
                },
                TextToolMode(id: "utf8", title: "UTF-8-Bytes", systemImage: "number") { input in
                    Array(input.utf8)
                        .map { String(format: "%02X", $0) }
                        .joined(separator: " ")
                },
                TextToolMode(id: "escape", title: "Als \\u escapen", systemImage: "backslash") { input in
                    input.unicodeScalars
                        .map { scalar in
                            scalar.isASCII
                                ? String(scalar)
                                : String(format: "\\u{%04X}", scalar.value)
                        }
                        .joined()
                }
            ]
        )
    }

    /// The characters that cause bug reports: things that look like a space but
    /// are not, and things that are not there at all.
    static let suspiciousScalars: Set<UInt32> = [
        0x00A0, // geschütztes Leerzeichen
        0x200B, 0x200C, 0x200D, // Nullbreiten
        0x2018, 0x2019, 0x201C, 0x201D, // typografische Anführungszeichen
        0x2013, 0x2014, // Halbgeviert- und Geviertstrich
        0x00AD, // weiches Trennzeichen
        0xFEFF // Byte-Order-Mark
    ]

    static func describeCharacters(_ input: String, suspiciousOnly: Bool) throws -> String {
        guard !input.isEmpty else {
            throw AnvilError.invalidInput(localized("Da ist kein Text zum Anschauen."))
        }

        let lines = input.unicodeScalars.compactMap { scalar -> String? in
            let isSuspicious = suspiciousScalars.contains(scalar.value)
                || (!scalar.isASCII && scalar.properties.isWhitespace)
            if suspiciousOnly, !isSuspicious { return nil }

            let display = scalar.properties.isWhitespace || scalar.value < 0x20
                ? "·"
                : String(scalar)
            let name = scalar.properties.name ?? localized("ohne Namen")
            let bytes = Array(String(scalar).utf8)
                .map { String(format: "%02X", $0) }
                .joined(separator: " ")

            return "\(display)  U+\(String(format: "%04X", scalar.value))  \(bytes.padding(toLength: max(bytes.count, 11), withPad: " ", startingAt: 0))  \(name)"
        }

        guard !lines.isEmpty else {
            return localized("Nichts Auffälliges — nur gewöhnliche Zeichen.")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - File permissions

    static var permissions: TextTool {
        TextTool(
            id: "dev.permissions",
            title: "Dateirechte",
            subtitle: "chmod-Zahlen und rwx",
            systemImage: "lock.doc",
            category: .coding,
            keywords: ["chmod", "rechte", "permissions", "rwx", "755", "644", "unix", "datei"],
            placeholder: "755 · rwxr-xr-x · 644",
            modes: [
                TextToolMode(id: "convert", title: "Umrechnen", systemImage: "arrow.left.arrow.right") { input in
                    let bits = try parsePermissions(input)
                    return input.contains(where: \.isLetter)
                        ? octalPermissions(bits)
                        : symbolicPermissions(bits)
                },
                TextToolMode(id: "explain", title: "Erklären", systemImage: "text.bubble") { input in
                    let bits = try parsePermissions(input)
                    return explainPermissions(bits)
                }
            ]
        )
    }

    /// Nine bits, owner-group-others, read-write-execute.
    static func parsePermissions(_ input: String) throws -> [Bool] {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.allSatisfy(\.isNumber) {
            guard text.count == 3, let value = Int(text, radix: 8), value <= 0o777 else {
                throw AnvilError.invalidInput(localized("chmod-Zahlen haben drei Ziffern von 0 bis 7."))
            }
            return (0..<9).reversed().map { value & (1 << $0) != 0 }
        }

        let symbols = text.count == 10 ? String(text.dropFirst()) : text
        guard symbols.count == 9 else {
            throw AnvilError.invalidInput(
                localized("Das sind weder drei Ziffern noch neun Zeichen wie rwxr-xr-x.")
            )
        }

        return symbols.enumerated().map { index, character in
            character == permissionLetters[index % 3]
                || (index % 3 == 2 && "sSt".contains(character))
        }
    }

    static func octalPermissions(_ bits: [Bool]) -> String {
        stride(from: 0, to: 9, by: 3)
            .map { offset in
                let value = (bits[offset] ? 4 : 0) + (bits[offset + 1] ? 2 : 0) + (bits[offset + 2] ? 1 : 0)
                return String(value)
            }
            .joined()
    }

    static func symbolicPermissions(_ bits: [Bool]) -> String {
        bits.enumerated()
            .map { index, isSet in isSet ? String(permissionLetters[index % 3]) : "-" }
            .joined()
    }

    static let permissionLetters: [Character] = ["r", "w", "x"]

    static func explainPermissions(_ bits: [Bool]) -> String {
        let groups = [localized("Eigentümer"), localized("Gruppe"), localized("Alle anderen")]
        let rights = [localized("lesen"), localized("schreiben"), localized("ausführen")]

        let lines = groups.enumerated().map { groupIndex, group -> String in
            let allowed = rights.enumerated()
                .filter { bits[groupIndex * 3 + $0.offset] }
                .map(\.element)
            let summary = allowed.isEmpty ? localized("nichts") : allowed.joined(separator: ", ")
            return "\(group): \(summary)"
        }

        return ([octalPermissions(bits) + "  " + symbolicPermissions(bits), ""] + lines)
            .joined(separator: "\n")
    }

    // MARK: - HTTP status codes

    static var statusCodes: TextTool {
        TextTool(
            id: "dev.http",
            title: "HTTP-Codes",
            subtitle: "Was 418 eigentlich heißt",
            systemImage: "arrow.up.arrow.down.square",
            category: .coding,
            keywords: ["http", "status", "code", "404", "500", "rest", "api", "fehler"],
            isMonospaced: false,
            placeholder: "404 · 5 für alle Serverfehler",
            modes: [
                TextToolMode(id: "lookup", title: "Nachschlagen", systemImage: "magnifyingglass") { input in
                    try lookUpStatus(input)
                }
            ]
        )
    }

    static func lookUpStatus(_ input: String) throws -> String {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(text.prefix(while: \.isNumber)), !text.isEmpty else {
            throw AnvilError.invalidInput(localized("Trag eine Zahl ein — 404, oder 4 für alle davon."))
        }

        if number < 10 {
            let matching = statusTable
                .filter { $0.key / 100 == number }
                .sorted { $0.key < $1.key }
            guard !matching.isEmpty else {
                throw AnvilError.invalidInput(localized("Diese Klasse gibt es nicht."))
            }
            return matching.map { "\($0.key)  \($0.value.0) — \($0.value.1)" }.joined(separator: "\n")
        }

        guard let entry = statusTable[number] else {
            throw AnvilError.invalidInput(localized("Den Code \(number) kenne ich nicht."))
        }
        return "\(number) \(entry.0)\n\n\(entry.1)"
    }

    /// Name and what it actually means, not what the RFC says.
    static let statusTable: [Int: (String, String)] = [
        200: ("OK", localized("Hat geklappt.")),
        201: ("Created", localized("Angelegt. Die Adresse steht im Location-Header.")),
        204: ("No Content", localized("Hat geklappt, es gibt nur nichts zurückzugeben.")),
        301: ("Moved Permanently", localized("Umgezogen, für immer. Lesezeichen aktualisieren.")),
        302: ("Found", localized("Vorübergehend woanders.")),
        304: ("Not Modified", localized("Nimm, was du im Cache hast.")),
        307: ("Temporary Redirect", localized("Wie 302, aber die Methode bleibt erhalten.")),
        308: ("Permanent Redirect", localized("Wie 301, aber die Methode bleibt erhalten.")),
        400: ("Bad Request", localized("Die Anfrage ergibt keinen Sinn — Tippfehler im Body oder in den Parametern.")),
        401: ("Unauthorized", localized("Nicht angemeldet. Heißt Unauthorized, meint Unauthenticated.")),
        403: ("Forbidden", localized("Angemeldet, aber nicht befugt.")),
        404: ("Not Found", localized("Gibt es nicht — oder du darfst nicht wissen, dass es das gibt.")),
        405: ("Method Not Allowed", localized("Die Adresse gibt es, diese Methode nicht.")),
        409: ("Conflict", localized("Kollidiert mit dem, was schon da ist.")),
        410: ("Gone", localized("Gab es, gibt es absichtlich nicht mehr.")),
        413: ("Payload Too Large", localized("Zu viel geschickt.")),
        415: ("Unsupported Media Type", localized("Falscher Content-Type.")),
        418: ("I'm a teapot", localized("Aprilscherz von 1998, steht bis heute in der Spezifikation.")),
        422: ("Unprocessable Content", localized("Syntaktisch in Ordnung, inhaltlich nicht.")),
        429: ("Too Many Requests", localized("Zu schnell. Retry-After beachten.")),
        500: ("Internal Server Error", localized("Etwas ist abgestürzt und niemand hat es abgefangen.")),
        501: ("Not Implemented", localized("Kennt der Server nicht.")),
        502: ("Bad Gateway", localized("Der Server hat weiter hinten eine kaputte Antwort bekommen.")),
        503: ("Service Unavailable", localized("Überlastet oder in Wartung.")),
        504: ("Gateway Timeout", localized("Weiter hinten hat niemand rechtzeitig geantwortet."))
    ]

    // MARK: - Cron

    static var cron: TextTool {
        TextTool(
            id: "dev.cron",
            title: "Cron",
            subtitle: "Ausdruck lesen und nächste Termine",
            systemImage: "calendar.badge.clock",
            category: .coding,
            keywords: ["cron", "crontab", "zeitplan", "schedule", "job", "timer"],
            placeholder: "*/5 * * * · 0 9 * * 1-5",
            modes: [
                TextToolMode(id: "explain", title: "Erklären", systemImage: "text.bubble") { input in
                    let expression = try CronExpression(parsing: input)
                    let upcoming = expression.upcoming(count: 3)
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.dateFormat = "dd.MM.yyyy HH:mm"

                    let dates = upcoming.map { formatter.string(from: $0) }
                    guard !dates.isEmpty else { return expression.explanation }

                    return expression.explanation
                        + "\n\n"
                        + localized("Nächste Termine:")
                        + "\n"
                        + dates.map { "- \($0)" }.joined(separator: "\n")
                }
            ]
        )
    }
}
