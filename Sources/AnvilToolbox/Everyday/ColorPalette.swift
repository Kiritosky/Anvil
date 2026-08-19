import AnvilKit
import Foundation

/// Eine ganze Farbliste auf einmal.
public struct ColorPalette: Sendable {
    public struct Entry: Sendable, Identifiable, Hashable {
        public let id: Int
        /// Was in der Zeile stand — ohne Namen und Beiwerk.
        public let source: String
        /// Der Name davor, sofern einer dastand.
        public let name: String
        public let color: ColorValue?

        public var isReadable: Bool { color != nil }
        /// Wie die Zeile in einer Tabelle heißt.
        public var label: String { name.isEmpty ? source : name }

        public init(id: Int, source: String, name: String, color: ColorValue?) {
            self.id = id
            self.source = source
            self.name = name
            self.color = color
        }
    }

    /// Zwei Farben, die zu nah beieinander liegen, um zwei zu sein.
    public struct Twin: Sendable, Hashable, Identifiable {
        public let first: Entry
        public let second: Entry
        /// 0 heißt: dieselbe Farbe.
        public let distance: Double

        public var id: String { "\(first.id)-\(second.id)" }
        public var isIdentical: Bool { distance == 0 }
    }

    public let entries: [Entry]

    public var isEmpty: Bool { entries.isEmpty }
    public var readable: [Entry] { entries.filter(\.isReadable) }
    public var unreadable: [Entry] { entries.filter { !$0.isReadable } }
    public var colors: [ColorValue] { entries.compactMap(\.color) }

    public static let empty = ColorPalette(entries: [])

    init(entries: [Entry]) {
        self.entries = entries
    }

    // MARK: - Lesen

    /// Liest eine Farbe je Zeile.
    public init(_ text: String) {
        entries = TextLines.split(text, keepingEmpty: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, line in Self.read(line, id: index) }
    }

    static func read(_ line: String, id: Int) -> Entry {
        let cleaned = line
            .replacingOccurrences(of: ";", with: " ")
            .replacingOccurrences(of: ",", with: ", ")
            .trimmingCharacters(in: .whitespaces)

        if let range = cleaned.range(of: #"(rgba?|hsla?)\([^)]*\)"#, options: .regularExpression) {
            let value = String(cleaned[range])
            let name = String(cleaned[cleaned.startIndex..<range.lowerBound])
            return Entry(
                id: id,
                source: value,
                name: Self.cleanName(name),
                color: ColorValue(parsing: value)
            )
        }

        let words = cleaned.split(separator: " ").map(String.init)
        for (offset, word) in words.enumerated().reversed() {
            guard let color = ColorValue(parsing: word) else { continue }
            let name = words[words.startIndex..<offset].joined(separator: " ")
            return Entry(id: id, source: word, name: Self.cleanName(name), color: color)
        }
        return Entry(id: id, source: cleaned, name: "", color: nil)
    }

    /// Namen stehen in Stilvorlagen als `--marke:` oder `marke =` da.
    static func cleanName(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " -:=\"'"))
    }

    // MARK: - Was zwischen den Farben passiert

    /// Ab wann zwei Farben als dieselbe durchgehen.
    public static let twinThreshold = 3.0 / 255

    /// Farben, die zu nah beieinander liegen, um zwei zu sein.
    public func twins(threshold: Double = ColorPalette.twinThreshold) -> [Twin] {
        var result: [Twin] = []
        let entries = readable
        for (index, entry) in entries.enumerated() {
            guard let first = entry.color else { continue }
            for other in entries.dropFirst(index + 1) {
                guard let second = other.color else { continue }
                let distance = Self.distance(first, second)
                guard distance <= threshold else { continue }
                result.append(Twin(first: entry, second: other, distance: distance))
            }
        }
        return result
    }

    /// Der größte Unterschied eines einzelnen Kanals.
    static func distance(_ first: ColorValue, _ second: ColorValue) -> Double {
        max(
            abs(first.red - second.red),
            abs(first.green - second.green),
            abs(first.blue - second.blue)
        )
    }

    // MARK: - Ausgeben

    public static let reportColumns = [
        localized("Name"),
        localized("Hex"),
        localized("RGB"),
        localized("HSL"),
        localized("auf Weiß"),
        localized("auf Schwarz")
    ]

    public func row(_ entry: Entry) -> [String] {
        guard let color = entry.color else {
            return [entry.label, "—", "—", "—", "—", "—"]
        }
        return [
            entry.label,
            color.hex,
            color.rgbNotation,
            color.hslNotation,
            Self.ratio(color.contrast(with: ColorValue(red: 1, green: 1, blue: 1))),
            Self.ratio(color.contrast(with: ColorValue(red: 0, green: 0, blue: 0)))
        ]
    }

    static func ratio(_ value: Double) -> String {
        String(format: "%.2f:1", value)
    }

    public var report: String {
        let header = Self.reportColumns.joined(separator: "\t")
        return ([header] + entries.map { row($0).joined(separator: "\t") })
            .joined(separator: "\n")
    }

    /// Die Palette als CSS-Variablen.
    public var css: String {
        var lines = [":root {"]
        for (index, entry) in readable.enumerated() {
            guard let color = entry.color else { continue }
            lines.append("  --\(Self.identifier(entry.name, fallback: index + 1)): \(color.hex);")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// Die Palette als SwiftUI-Farben.
    public var swift: String {
        readable.compactMap { entry -> String? in
            guard let color = entry.color else { return nil }
            let name = Self.identifier(entry.name, fallback: entry.id + 1, camelCase: true)
            return "static let \(name) = \(color.swiftUINotation)"
        }
        .joined(separator: "\n")
    }

    /// Macht aus einem Namen einen Bezeichner — oder eine Nummer daraus.
    static func identifier(_ name: String, fallback: Int, camelCase: Bool = false) -> String {
        let parts = name
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
            .lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)

        guard !parts.isEmpty else { return camelCase ? "farbe\(fallback)" : "farbe-\(fallback)" }
        guard camelCase else { return parts.joined(separator: "-") }

        let head = parts[0]
        let tail = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let joined = ([head] + tail).joined()
        return joined.first?.isNumber == true ? "farbe\(joined)" : joined
    }
}
