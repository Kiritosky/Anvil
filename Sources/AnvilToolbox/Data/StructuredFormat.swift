import AnvilKit
import Foundation

/// Eines der drei Formate, die dasselbe meinen.
public enum StructuredFormat: String, Sendable, Hashable, CaseIterable, Identifiable {
    case json
    case yaml
    case toml

    public var id: String { rawValue }

    /// Der Name des Formats — in jeder Sprache derselbe.
    public var title: String {
        switch self {
        case .json: "JSON"
        case .yaml: "YAML"
        case .toml: "TOML"
        }
    }

    public var systemImage: String {
        switch self {
        case .json: "curlybraces"
        case .yaml: "list.bullet.indent"
        case .toml: "square.split.1x2"
        }
    }

    /// Die Endung, die eine geschriebene Datei bekommt.
    public var fileExtension: String { rawValue }

    /// Die Endungen, an denen sich das Format ohne Hineinsehen erkennen lässt.
    public var fileExtensions: [String] {
        switch self {
        case .json: ["json"]
        case .yaml: ["yaml", "yml"]
        case .toml: ["toml"]
        }
    }

    public static func named(_ fileExtension: String) -> StructuredFormat? {
        let wanted = fileExtension.lowercased()
        return allCases.first { $0.fileExtensions.contains(wanted) }
    }

    // MARK: - Lesen und schreiben

    public func read(_ text: String) throws -> StructuredValue {
        switch self {
        case .json: try StructuredValue.json(parsing: text)
        case .yaml: try StructuredValue.yaml(parsing: text)
        case .toml: try StructuredValue.toml(parsing: text)
        }
    }

    public func write(_ value: StructuredValue) -> String {
        switch self {
        case .json: value.jsonText
        case .yaml: value.yamlText
        case .toml: value.tomlText
        }
    }

    // MARK: - Raten

    /// Rät das Format am Anfang des Textes.
    public static func detect(_ text: String) -> StructuredFormat {
        let lines = TextLines.split(text, keepingEmpty: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard let first = lines.first else { return .json }

        if first.hasPrefix("{") { return .json }
        if first.hasPrefix("[") {
            let inner = first.dropFirst().drop { $0 == "[" }.prefix { $0 != "]" }
            let looksLikeTable = !inner.isEmpty && inner.allSatisfy {
                $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." || $0 == "\""
            }
            return looksLikeTable ? .toml : .json
        }
        for line in lines.prefix(20) {
            if line.hasPrefix("[") { return .toml }
            guard let equals = line.firstIndex(of: "=") else { continue }
            guard let colon = line.firstIndex(of: ":") else { return .toml }
            if equals < colon { return .toml }
        }
        return .yaml
    }

    /// Rät das Format einer Datei.
    public static func detect(name: String, text: String) -> StructuredFormat {
        let fileExtension = URL(fileURLWithPath: name).pathExtension
        return named(fileExtension) ?? detect(text)
    }
}
