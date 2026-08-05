import Foundation
import Testing

@testable import AnvilKit

@Suite("Localization")
struct LocalizationTests {
    @Test
    func germanIsTheDevelopmentLanguage() {
        #expect(Localization.developmentLanguage == "de")
        #expect(Localization.supportedLanguages.contains("de"))
        #expect(Localization.supportedLanguages.contains("en"))
    }

    @Test
    func unknownKeysFallBackToThemselves() {
        // The whole point of using the German source text as the key: a missing
        // entry shows correct German rather than an identifier.
        let text = "Ein Satz, den mit Sicherheit niemand übersetzt hat."
        #expect(localized(runtime: text) == text)
    }

    @Test
    func emptyStringsAreLeftAlone() {
        #expect(localized(runtime: "").isEmpty)
    }

    @Test @MainActor
    func toolMetadataLocalisesItsDisplayText() {
        // Without a translation bundle the strings pass through unchanged; what
        // matters here is that nothing is mangled on the way.
        let metadata = ToolMetadata(
            id: "test.tool",
            title: "Prüfsummen",
            subtitle: "MD5, SHA-1, SHA-256",
            systemImage: "number",
            category: .coding,
            keywords: ["hash", "prüfsumme"],
            badge: "Neu"
        )

        #expect(metadata.title == "Prüfsummen")
        #expect(metadata.subtitle == "MD5, SHA-1, SHA-256")
        #expect(metadata.keywords == ["hash", "prüfsumme"])
        #expect(metadata.badge == "Neu")
        #expect(metadata.searchCorpus.contains("Prüfsummen"))
    }

    @Test
    func categoriesKeepTheirIdentifierWhileTranslatingTheTitle() {
        // The identifier is data and must never change with the language —
        // it is what user tool files reference in `categoryID`.
        #expect(ToolCategory.coding.id == "coding")
        #expect(ToolCategory.speech.id == "speech")
        #expect(!ToolCategory.coding.title.isEmpty)
    }

    @Test
    func errorsCarryTranslatedTitleAndMessage() {
        let error = AnvilError.invalidInput("Da ist noch nichts.")
        #expect(!error.title.isEmpty)
        #expect(error.message == "Da ist noch nichts.")
    }
}
