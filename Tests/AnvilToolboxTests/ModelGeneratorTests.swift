import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Aus JSON Typen ableiten")
struct ModelGeneratorTests {
    private func model(_ json: String, rootName: String = "Root") throws -> ModelGenerator {
        ModelGenerator.infer(try StructuredValue.json(parsing: json), rootName: rootName)
    }

    @Test
    func scalarsBecomeTheObviousTypes() throws {
        let model = try model(#"{"name":"Anna","alter":42,"quote":1.5,"aktiv":true}"#)
        let swift = model.text(.swift)
        #expect(swift.contains("let name: String"))
        #expect(swift.contains("let alter: Int"))
        #expect(swift.contains("let quote: Double"))
        #expect(swift.contains("let aktiv: Bool"))
    }

    /// Der Wurzeltyp steht oben. Sonst begänne die Datei mit dem
    /// Kleingedruckten.
    @Test
    func theRootTypeComesFirst() throws {
        let model = try model(#"{"adresse":{"ort":"Kiel"}}"#)
        #expect(model.types.map(\.name) == ["Root", "Adresse"])
        let swift = model.text(.swift)
        let root = try #require(swift.range(of: "struct Root"))
        let nested = try #require(swift.range(of: "struct Adresse"))
        #expect(root.lowerBound < nested.lowerBound)
    }

    @Test
    func aNestedObjectBecomesItsOwnType() throws {
        let model = try model(#"{"adresse":{"ort":"Kiel","plz":24103}}"#)
        #expect(model.types.count == 2)
        #expect(model.text(.swift).contains("let adresse: Adresse"))
        #expect(model.text(.swift).contains("let plz: Int"))
    }

    @Test
    func aListOfScalarsBecomesAnArray() throws {
        let model = try model(#"{"tags":["eins","zwei"]}"#)
        #expect(model.text(.swift).contains("let tags: [String]"))
        #expect(model.text(.typescript).contains("tags: string[]"))
    }

    /// Der eigentliche Gewinn: Was nicht in jedem Element steht, ist optional.
    @Test
    func aFieldMissingFromOneElementIsOptional() throws {
        let model = try model(#"{"leute":[{"name":"Anna","spitzname":"Ann"},{"name":"Bo"}]}"#)
        let swift = model.text(.swift)
        #expect(swift.contains("let name: String"))
        #expect(swift.contains("let spitzname: String?"))
        #expect(model.optionalCount == 1)
    }

    /// Ein Feld, das im ersten Element `null` ist, verrät seinen Typ im
    /// zweiten — optional bleibt es trotzdem.
    @Test
    func aNullInTheFirstElementDoesNotDecideTheType() throws {
        let model = try model(#"{"leute":[{"alter":null},{"alter":30}]}"#)
        #expect(model.text(.swift).contains("let alter: Int?"))
    }

    @Test
    func aFieldThatIsOnlyEverNullBecomesAnOptionalString() throws {
        let model = try model(#"{"rest":null}"#)
        #expect(model.text(.swift).contains("let rest: String?"))
        #expect(model.text(.typescript).contains("rest?: unknown;"))
    }

    /// Die Liste heißt „leute", der Typ darin „Leut" — eine Faustregel, keine
    /// Grammatik. Wichtiger ist, dass sie überhaupt einen eigenen Namen
    /// bekommt.
    @Test
    func aListOfObjectsGetsASingularTypeName() throws {
        let model = try model(#"{"entries":[{"a":1}]}"#)
        #expect(model.types.map(\.name) == ["Root", "Entry"])
        #expect(model.text(.swift).contains("let entries: [Entry]"))
    }

    @Test
    func aMixedListIsNotGuessed() throws {
        let model = try model(#"{"bunt":[1,"zwei"]}"#)
        #expect(model.text(.swift).contains("let bunt: [String]"))
        #expect(model.text(.typescript).contains("bunt: unknown[]"))
    }

    @Test
    func anEmptyListIsNotGuessedEither() throws {
        let model = try model(#"{"leer":[]}"#)
        #expect(model.text(.typescript).contains("leer: unknown[]"))
    }

    // MARK: - Namen

    @Test
    func snakeCaseBecomesCamelCaseWithCodingKeys() throws {
        let model = try model(#"{"created_at":"2026-01-15"}"#)
        let swift = model.text(.swift)
        #expect(swift.contains("let createdAt: String"))
        #expect(swift.contains("enum CodingKeys: String, CodingKey"))
        #expect(swift.contains("case createdAt = \"created_at\""))
    }

    /// Ohne Umbenennung braucht es keinen Block — und ein Block, der nichts
    /// tut, ist Quelltext, den jemand später sucht.
    @Test
    func nothingRenamedMeansNoCodingKeys() throws {
        let model = try model(#"{"name":"Anna"}"#)
        #expect(!model.text(.swift).contains("CodingKeys"))
    }

    @Test
    func aSwiftKeywordGetsBackticks() {
        #expect(ModelGenerator.propertyName("class") == "`class`")
        #expect(ModelGenerator.propertyName("name") == "name")
        #expect(ModelGenerator.propertyName("2fa") == "_2fa")
    }

    @Test
    func typeNamesBecomePascalCase() {
        #expect(ModelGenerator.typeName("created_at") == "CreatedAt")
        #expect(ModelGenerator.typeName("adress-buch") == "AdressBuch")
        #expect(ModelGenerator.typeName("") == "Wert")
    }

    /// Zwei Felder desselben Namens in verschiedenen Zweigen dürfen nicht
    /// denselben Typ überschreiben.
    @Test
    func twoTypesOfTheSameNameAreCountedUp() throws {
        let model = try model(#"{"a":{"wert":{"x":1}},"b":{"wert":{"y":2}}}"#)
        let names = model.types.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.contains("Wert"))
        #expect(names.contains("Wert2"))
    }

    // MARK: - TypeScript

    @Test
    func typeScriptKeepsTheKeyAndMarksOptionals() throws {
        let model = try model(#"{"leute":[{"created_at":"x","nur_hier":1},{"created_at":"y"}]}"#)
        let text = model.text(.typescript)
        #expect(text.contains("export interface Root {"))
        #expect(text.contains("created_at: string;"))
        #expect(text.contains("nur_hier?: number;"))
    }

    @Test
    func aKeyThatIsNoIdentifierIsQuoted() throws {
        let model = try model(#"{"content-type":"json"}"#)
        #expect(model.text(.typescript).contains("\"content-type\": string;"))
    }

    // MARK: - Übersicht

    @Test
    func theTableHasALinePerField() throws {
        let model = try model(#"{"a":1,"b":{"c":"x"}}"#)
        #expect(model.rows().count == model.fieldCount)
        #expect(model.rows().allSatisfy { $0.count == ModelGenerator.reportColumns.count })
    }

    @Test
    func nothingInNothingOut() {
        #expect(ModelGenerator.empty.isEmpty)
        #expect(ModelGenerator.empty.text(.swift).isEmpty)
        #expect(ModelGenerator.empty.fieldCount == 0)
    }
}
