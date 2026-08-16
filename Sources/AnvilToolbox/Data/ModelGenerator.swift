import AnvilKit
import Foundation

/// Aus einer Beispielantwort werden Typen.
///
/// Das ist die Handarbeit, die jeder einmal pro API macht: Man bekommt einen
/// JSON-Schnipsel, tippt ihn als `struct` ab, vergisst ein Feld, schreibt
/// `Int` wo `Double` steht, und merkt beides erst, wenn das Dekodieren
/// fehlschlägt. Die Antwort steht schon da — abgeschrieben werden muss sie
/// nicht.
public struct ModelGenerator: Sendable {
    /// Wofür Typen erzeugt werden.
    public enum Language: String, Sendable, Hashable, CaseIterable, Identifiable {
        case swift
        case typescript

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .swift: "Swift"
            case .typescript: "TypeScript"
            }
        }

        public var systemImage: String {
            switch self {
            case .swift: "swift"
            case .typescript: "curlybraces"
            }
        }

        public var fileExtension: String {
            switch self {
            case .swift: "swift"
            case .typescript: "ts"
            }
        }
    }

    /// Der Typ eines Feldes.
    public indirect enum FieldType: Sendable, Hashable {
        case string
        case integer
        case double
        case boolean
        /// Im Beispiel stand nur `null` — mehr lässt sich nicht sagen.
        case unknown
        case array(FieldType)
        /// Ein eigener Typ, unter diesem Namen erzeugt.
        case object(String)
    }

    public struct Field: Sendable, Hashable {
        public let key: String
        public let type: FieldType
        public let isOptional: Bool

        public init(key: String, type: FieldType, isOptional: Bool) {
            self.key = key
            self.type = type
            self.isOptional = isOptional
        }
    }

    public struct ObjectType: Sendable, Hashable, Identifiable {
        public let name: String
        public let fields: [Field]

        public var id: String { name }
    }

    public let types: [ObjectType]

    public init(types: [ObjectType]) {
        self.types = types
    }

    public static let empty = ModelGenerator(types: [])

    public var isEmpty: Bool { types.isEmpty }

    public var fieldCount: Int { types.reduce(0) { $0 + $1.fields.count } }

    public var optionalCount: Int {
        types.reduce(0) { $0 + $1.fields.filter(\.isOptional).count }
    }

    // MARK: - Ableiten

    /// Leitet die Typen aus einem Beispielwert ab.
    public static func infer(_ value: StructuredValue, rootName: String = "Root") -> ModelGenerator {
        var builder = Builder()
        _ = builder.build(value, named: rootName)
        return ModelGenerator(types: builder.types)
    }

    /// Der Zustand während des Ableitens.
    ///
    /// Eigener Typ, weil zwei Dinge über den ganzen Baum mitlaufen: die schon
    /// vergebenen Typnamen und die Reihenfolge, in der die Typen entstehen.
    private struct Builder {
        var types: [ObjectType] = []
        var used: Set<String> = []

        mutating func build(_ value: StructuredValue, named name: String) -> FieldType {
            switch value {
            case .string: .string
            case let .number(number): number == number.rounded() ? .integer : .double
            case .boolean: .boolean
            case .null: .unknown
            case let .array(elements): buildArray(elements, named: name)
            case let .object(pairs): buildObject(pairs.map { Entry($0) }, named: name)
            }
        }

        private mutating func buildArray(
            _ elements: [StructuredValue],
            named name: String
        ) -> FieldType {
            guard !elements.isEmpty else { return .array(.unknown) }

            // Objekte in einer Liste beschreiben dasselbe Ding — aber selten
            // vollständig. Das erste Element hat manchmal ein Feld, das dem
            // zweiten fehlt, und genau das ist die Auskunft, die man will:
            // Das Feld ist optional.
            if elements.allSatisfy({ $0.pairs != nil }) {
                return .array(buildObject(merged(elements), named: singular(name)))
            }

            var found: [FieldType] = []
            for element in elements {
                found.append(build(element, named: singular(name)))
            }
            // Eine Liste, in der Zahlen und Text durcheinanderstehen, ist
            // nichts, worüber sich raten lässt.
            guard let first = found.first, found.allSatisfy({ $0 == first }) else {
                return .array(.unknown)
            }
            return .array(first)
        }

        private mutating func buildObject(
            _ pairs: [Entry],
            named name: String
        ) -> FieldType {
            let typeName = unique(Self.typeName(name))
            // Der Platz wird vorher belegt, damit der Wurzeltyp oben steht:
            // Sonst entstünden die inneren Typen zuerst und die Datei begänne
            // mit dem Kleingedruckten.
            let index = types.count
            types.append(ObjectType(name: typeName, fields: []))

            // Eine Schleife statt `map`: Jeder Schritt legt weitere Typen an,
            // und ein Abschluss darf `self` einer Struktur nicht verändern.
            var fields: [Field] = []
            for pair in pairs {
                fields.append(
                    Field(
                        key: pair.key,
                        type: build(pair.value, named: pair.key),
                        isOptional: pair.isOptional || pair.value == .null
                    )
                )
            }

            types[index] = ObjectType(name: typeName, fields: fields)
            return .object(typeName)
        }

        /// Ein Paar samt der Auskunft, ob es überall vorkam.
        struct Entry {
            let key: String
            let value: StructuredValue
            let isOptional: Bool

            init(_ pair: StructuredValue.Pair) {
                key = pair.key
                value = pair.value
                isOptional = false
            }

            init(key: String, value: StructuredValue, isOptional: Bool) {
                self.key = key
                self.value = value
                self.isOptional = isOptional
            }
        }

        /// Legt die Objekte einer Liste übereinander.
        private func merged(_ elements: [StructuredValue]) -> [Entry] {
            var order: [String] = []
            var values: [String: StructuredValue] = [:]
            var seen: [String: Int] = [:]
            var nulled: Set<String> = []

            for element in elements {
                for pair in element.pairs ?? [] {
                    if values[pair.key] == nil {
                        order.append(pair.key)
                    }
                    // Der erste Wert, der nicht `null` ist, sagt am meisten:
                    // `null` verrät den Typ nicht, das nächste Element schon.
                    if values[pair.key] == nil || values[pair.key] == StructuredValue.null {
                        values[pair.key] = pair.value
                    }
                    if pair.value == .null { nulled.insert(pair.key) }
                    seen[pair.key, default: 0] += 1
                }
            }

            return order.map { key in
                Entry(
                    key: key,
                    value: values[key] ?? .null,
                    // Fehlt das Feld irgendwo oder stand dort `null`, ist es
                    // optional — beides heißt beim Dekodieren dasselbe.
                    isOptional: seen[key, default: 0] < elements.count || nulled.contains(key)
                )
            }
        }

        private mutating func unique(_ name: String) -> String {
            guard used.contains(name) else {
                used.insert(name)
                return name
            }
            for number in 2...999 {
                let candidate = "\(name)\(number)"
                if !used.contains(candidate) {
                    used.insert(candidate)
                    return candidate
                }
            }
            return name
        }

        /// „adressen" → „Adresse", „entries" → „Entry".
        ///
        /// Eine Faustregel und keine Grammatik: Sie trifft die Fälle, die in
        /// JSON vorkommen, und wo sie danebenliegt, steht ein Name da, den man
        /// in einem Zug umbenennt.
        private func singular(_ name: String) -> String {
            if name.hasSuffix("ies"), name.count > 3 {
                return String(name.dropLast(3)) + "y"
            }
            if name.hasSuffix("s"), !name.hasSuffix("ss"), name.count > 1 {
                return String(name.dropLast())
            }
            return name
        }

        static func typeName(_ key: String) -> String {
            ModelGenerator.typeName(key)
        }
    }

    /// Der Name, unter dem ein Typ im Quelltext steht.
    ///
    /// `created_at` wird `CreatedAt`, `adress-buch` wird `AdressBuch`. Was
    /// übrig bleibt, wenn nichts davon greift, heißt `Wert` — ein Name, den
    /// man sofort ändert, statt einen leeren zu suchen.
    public static func typeName(_ key: String) -> String {
        let parts = key
            .components(separatedBy: CharacterSet(charactersIn: "_- ."))
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "Wert" }
        return parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    // MARK: - Namen

    /// Der Name, unter dem ein Feld im Quelltext steht.
    ///
    /// `created_at` heißt in Swift `createdAt`; in JSON heißt es weiter
    /// `created_at`. Beides gleichzeitig geht nur über `CodingKeys` — deshalb
    /// entsteht der Block, sobald sich ein Name unterwegs ändert.
    public static func propertyName(_ key: String) -> String {
        let parts = key
            .components(separatedBy: CharacterSet(charactersIn: "_- ."))
            .filter { !$0.isEmpty }
        guard let first = parts.first else { return "wert" }

        let head = first.prefix(1).lowercased() + first.dropFirst()
        let tail = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let name = ([head] + tail).joined()

        // Ein Name, der mit einer Ziffer anfängt, ist in keiner der beiden
        // Sprachen ein Bezeichner.
        if let character = name.first, character.isNumber { return "_" + name }
        return swiftKeywords.contains(name) ? "`\(name)`" : name
    }

    /// Wörter, die in Swift nicht als Name durchgehen.
    static let swiftKeywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "func", "import",
        "init", "inout", "internal", "let", "operator", "private", "protocol",
        "public", "static", "struct", "subscript", "typealias", "var", "break",
        "case", "continue", "default", "defer", "do", "else", "fallthrough",
        "for", "guard", "if", "in", "repeat", "return", "switch", "where",
        "while", "as", "catch", "false", "is", "nil", "super", "self", "throw",
        "throws", "true", "try"
    ]

    // MARK: - Ausgeben

    public func text(_ language: Language) -> String {
        switch language {
        case .swift: swiftText
        case .typescript: typeScriptText
        }
    }

    private var swiftText: String {
        types.map { type in
            var lines = ["struct \(type.name): Codable {"]
            for field in type.fields {
                let name = Self.propertyName(field.key)
                lines.append("    let \(name): \(Self.swiftType(field.type))\(field.isOptional ? "?" : "")")
            }

            let renamed = type.fields.filter { Self.propertyName($0.key) != $0.key }
            if !renamed.isEmpty {
                lines.append("")
                lines.append("    enum CodingKeys: String, CodingKey {")
                for field in type.fields {
                    let name = Self.propertyName(field.key)
                    lines.append("        case \(name) = \"\(field.key)\"")
                }
                lines.append("    }")
            }

            lines.append("}")
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    private var typeScriptText: String {
        types.map { type in
            var lines = ["export interface \(type.name) {"]
            for field in type.fields {
                // In TypeScript bleibt der Schlüssel, wie er ist — dafür muss
                // er in Anführungszeichen, wenn er kein Bezeichner ist.
                let key = Self.isPlainIdentifier(field.key) ? field.key : "\"\(field.key)\""
                lines.append("  \(key)\(field.isOptional ? "?" : ""): \(Self.typeScriptType(field.type));")
            }
            lines.append("}")
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    static func isPlainIdentifier(_ key: String) -> Bool {
        guard let first = key.first, first.isLetter || first == "_" else { return false }
        return key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    static func swiftType(_ type: FieldType) -> String {
        switch type {
        case .string: "String"
        case .integer: "Int"
        case .double: "Double"
        case .boolean: "Bool"
        // Ein Feld, das im Beispiel nur `null` war, wird `String?`: Das ist
        // die Annahme, die am wenigsten kaputtmacht, wenn sie falsch ist.
        case .unknown: "String"
        case let .array(element): "[\(swiftType(element))]"
        case let .object(name): name
        }
    }

    static func typeScriptType(_ type: FieldType) -> String {
        switch type {
        case .string: "string"
        case .integer, .double: "number"
        case .boolean: "boolean"
        case .unknown: "unknown"
        case let .array(element): "\(typeScriptType(element))[]"
        case let .object(name): name
        }
    }

    // MARK: - Übersicht

    public static let reportColumns = [
        localized("Typ"),
        localized("Feld"),
        localized("Swift"),
        localized("TypeScript")
    ]

    public func rows() -> [[String]] {
        types.flatMap { type in
            type.fields.map { field in
                [
                    type.name,
                    field.key,
                    Self.swiftType(field.type) + (field.isOptional ? "?" : ""),
                    Self.typeScriptType(field.type) + (field.isOptional ? " | undefined" : "")
                ]
            }
        }
    }
}
