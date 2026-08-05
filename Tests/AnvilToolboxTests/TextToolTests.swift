import AnvilAI
import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("TextToolCatalog")
struct TextToolCatalogTests {
    private func run(_ tool: TextTool, _ modeID: String, _ input: String) throws -> String {
        try tool.run(input, modeID: modeID)
    }

    @Test
    func everyToolHasAtLeastOneMode() {
        for tool in TextToolCatalog.all {
            #expect(!tool.modes.isEmpty, "\(tool.title) hat keine Variante")
        }
    }

    @Test
    func toolIdentifiersAreUnique() {
        let ids = TextToolCatalog.all.map(\.id.rawValue)
        #expect(Set(ids).count == ids.count)
    }

    @Test
    func formatsAndMinifiesJSON() throws {
        let pretty = try run(TextToolCatalog.json, "pretty", "{\"a\":1}")
        #expect(pretty.contains("\n"))

        let minified = try run(TextToolCatalog.json, "minify", pretty)
        #expect(minified == "{\"a\":1}")
    }

    @Test
    func rejectsBrokenJSON() {
        #expect(throws: AnvilError.self) {
            try run(TextToolCatalog.json, "pretty", "{nope}")
        }
    }

    @Test
    func base64RoundTrips() throws {
        let encoded = try run(TextToolCatalog.base64, "encode", "Hallo Welt")
        #expect(encoded == "SGFsbG8gV2VsdA==")
        #expect(try run(TextToolCatalog.base64, "decode", encoded) == "Hallo Welt")
    }

    @Test
    func base64DecodesWithoutPadding() throws {
        #expect(try run(TextToolCatalog.base64, "decode", "SGFsbG8") == "Hallo")
    }

    @Test
    func urlEncodingRoundTrips() throws {
        let encoded = try run(TextToolCatalog.urlCoding, "encode", "a b&c")
        #expect(encoded == "a%20b%26c")
        #expect(try run(TextToolCatalog.urlCoding, "decode", encoded) == "a b&c")
    }

    @Test
    func convertsBetweenNamingConventions() throws {
        let tool = TextToolCatalog.caseConversion
        #expect(try run(tool, "camel", "hallo schöne welt") == "halloSchöneWelt")
        #expect(try run(tool, "snake", "halloSchoeneWelt") == "hallo_schoene_welt")
        #expect(try run(tool, "kebab", "HalloWelt") == "hallo-welt")
        #expect(try run(tool, "constant", "hallo welt") == "HALLO_WELT")
    }

    @Test
    func hashesAreStable() throws {
        let sha = try run(TextToolCatalog.hashes, "sha256", "abc")
        #expect(sha == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test
    func hexRoundTrips() throws {
        let encoded = try run(TextToolCatalog.hex, "encode", "Hi")
        #expect(encoded == "48 69")
        #expect(try run(TextToolCatalog.hex, "decode", encoded) == "Hi")
    }

    @Test
    func rejectsOddLengthHex() {
        #expect(throws: AnvilError.self) {
            try run(TextToolCatalog.hex, "decode", "abc")
        }
    }

    @Test
    func slugsAreURLSafe() throws {
        #expect(try run(TextToolCatalog.slug, "kebab", "Größe & Maß!") == "groesse-mass")
    }

    @Test
    func slugsKeepUmlautsApartFromPlainVowels() throws {
        // The two words differ in German, so their slugs have to differ too.
        let umlaut = try run(TextToolCatalog.slug, "kebab", "Größe")
        let plain = try run(TextToolCatalog.slug, "kebab", "Grosse")
        #expect(umlaut != plain)
    }

    @Test
    func slugsFoldAccentsFromOtherLanguages() throws {
        // Only German umlauts get the two-letter treatment; a French accent
        // just wants the plain letter.
        #expect(try run(TextToolCatalog.slug, "kebab", "Café crème") == "cafe-creme")
    }

    @Test
    func removesDuplicateLines() throws {
        let result = try run(TextToolCatalog.lines, "unique", "a\nb\na\nc")
        #expect(result == "a\nb\nc")
    }

    @Test
    func decodesJWTPayload() throws {
        // {"alg":"HS256"} . {"sub":"1234","name":"Anvil"} . signature
        let token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0IiwibmFtZSI6IkFudmlsIn0.sig"
        let decoded = try run(TextToolCatalog.jwt, "decode", token)
        #expect(decoded.contains("HS256"))
        #expect(decoded.contains("Anvil"))
    }

    @Test
    func rejectsMalformedJWT() {
        #expect(throws: AnvilError.self) {
            try run(TextToolCatalog.jwt, "decode", "nichtsvonalledem")
        }
    }
}

@Suite("AIPromptTool")
struct AIPromptToolTests {
    private var sample: AIPromptTool {
        AIPromptTool(
            id: "test.tool",
            title: "Test",
            subtitle: "",
            systemImage: "circle",
            instructions: "Ton: {{option:tone}}",
            promptTemplate: "Text: {{input}} (Ton: {{option:tone}})",
            options: [
                AIPromptOption(id: "tone", label: "Ton", choices: ["knapp", "locker"])
            ]
        )
    }

    @Test
    func fillsInputAndOptions() {
        let prompt = sample.buildPrompt(input: "Hallo", optionValues: ["tone": "locker"])
        #expect(prompt == "Text: Hallo (Ton: locker)")
    }

    @Test
    func fallsBackToTheDefaultOptionValue() {
        let prompt = sample.buildPrompt(input: "Hallo", optionValues: [:])
        #expect(prompt.contains("knapp"))
    }

    @Test
    func optionsAlsoReachTheInstructions() {
        let instructions = sample.buildInstructions(optionValues: ["tone": "locker"])
        #expect(instructions == "Ton: locker")
    }

    @Test
    func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(AIPromptTool.self, from: data)
        #expect(decoded.id == sample.id)
        #expect(decoded.options.first?.choices == ["knapp", "locker"])
    }

    @Test
    func builtInCatalogHasUniqueIdentifiers() {
        let ids = AIPromptCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test
    func everyCatalogToolStatesItsOutputRules() {
        for tool in AIPromptCatalog.all {
            #expect(tool.instructions.contains("Antworte"), "\(tool.title) sagt nicht, wie geantwortet werden soll")
            #expect(tool.promptTemplate.contains("{{input}}"), "\(tool.title) verwendet die Eingabe nicht")
        }
    }
}

@Suite("TextChunker")
struct TextChunkerTests {
    @Test
    func shortTextStaysInOnePiece() {
        let chunks = TextChunker.split("Kurzer Satz.", budget: 100)
        #expect(chunks.count == 1)
        #expect(chunks.first?.text == "Kurzer Satz.")
    }

    @Test
    func splitsOnParagraphBoundaries() {
        let text = String(repeating: "Ein Absatz mit etwas Text.", count: 4)
            + "\n\n"
            + String(repeating: "Noch ein Absatz mit Text.", count: 4)
        let chunks = TextChunker.split(text, budget: 120)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.text.count <= 130 })
    }

    @Test
    func splitsLongParagraphsOnSentences() {
        let text = String(repeating: "Das ist ein Satz. ", count: 30)
        let chunks = TextChunker.split(text, budget: 100)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { !$0.text.isEmpty })
    }

    @Test
    func chunkIdentifiersAreSequential() {
        let chunks = TextChunker.split(String(repeating: "Satz. ", count: 100), budget: 60)
        #expect(chunks.map(\.id) == Array(0..<chunks.count))
    }

    @Test
    func emptyInputProducesNoChunks() {
        #expect(TextChunker.split("   ", budget: 100).isEmpty)
    }
}
