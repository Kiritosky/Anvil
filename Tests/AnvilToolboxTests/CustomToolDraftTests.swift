import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Eigenes Werkzeug anlegen")
struct CustomToolDraftTests {
    private func draft(
        title: String = "Änderungstext schreiben",
        instructions: String = "Mach aus dem Diff eine Notiz."
    ) -> CustomToolDraft {
        var draft = CustomToolDraft()
        draft.title = title
        draft.instructions = instructions
        return draft
    }

    // MARK: - Kennung

    /// Die Kennung landet in Favoriten und im Fensterzustand — sie muss aus
    /// dem Titel stabil hervorgehen und darf nichts enthalten, was anderswo
    /// etwas bedeutet.
    @Test
    func theIdentifierComesFromTheTitle() {
        #expect(draft(title: "Änderungstext schreiben").identifier == "user.aenderungstext-schreiben")
        #expect(draft(title: "Größe").identifier == "user.groesse")
        #expect(draft(title: "A/B  Test!").identifier == "user.a-b-test")
    }

    /// Ein Titel, aus dem nichts übrig bleibt, darf nicht in „user." enden.
    @Test
    func aTitleOfPunctuationStillGivesAnIdentifier() {
        #expect(draft(title: "!!!").identifier == "user.werkzeug")
        #expect(draft(title: "").fileName == "werkzeug.json")
    }

    @Test
    func theFileNameFollowsTheIdentifier() {
        #expect(draft(title: "Notiz aus Diff").fileName == "notiz-aus-diff.json")
    }

    // MARK: - Was fehlt

    @Test
    func withoutATitleItIsNotReady() {
        let empty = draft(title: "")
        #expect(empty.problems().contains(.titleMissing))
        #expect(!empty.isReady())
    }

    @Test
    func withoutInstructionsItIsNotReady() {
        let empty = draft(instructions: "   \n  ")
        #expect(empty.problems().contains(.instructionsMissing))
        #expect(!empty.isReady())
    }

    /// Zwei Werkzeuge mit derselben Kennung heißt: Eines ersetzt das andere,
    /// und zwar lautlos.
    @Test
    func anIdentifierThatIsTakenBlocks() {
        let taken: Set<String> = ["user.aenderungstext-schreiben"]
        #expect(draft().problems(existing: taken).contains(.identifierTaken))
        #expect(!draft().isReady(existing: taken))
        // Ohne die fremde Kennung ist derselbe Entwurf in Ordnung.
        #expect(draft().isReady())
    }

    @Test
    func aFilledDraftIsReady() {
        #expect(draft().problems().isEmpty)
        #expect(draft().isReady())
    }

    // MARK: - Die Wahl

    @Test
    func anOptionNeedsAtLeastTwoChoices() {
        var one = draft()
        one.optionLabel = "Ausführlichkeit"
        one.optionChoices = "knapp"
        #expect(one.problems().contains(.optionWithoutChoices))
        #expect(!one.isReady())

        one.optionChoices = "knapp, normal"
        #expect(!one.problems().contains(.optionWithoutChoices))
    }

    /// Eine Wahl, die in der Anweisung nicht vorkommt, tut nichts — das ist
    /// ein Hinweis und kein Fehler, denn der Satz kommt vielleicht noch.
    @Test
    func anOptionThatIsNeverUsedIsOnlyAHint() {
        var unused = draft()
        unused.optionLabel = "Ausführlichkeit"
        unused.optionChoices = "knapp, normal"

        #expect(unused.problems().contains(.optionNotUsed))
        #expect(unused.isReady())
        #expect(CustomToolDraft.Problem.optionNotUsed.isBlocking == false)
    }

    @Test
    func theOptionPlaceholderMatchesTheIdentifier() {
        var withOption = draft()
        withOption.optionLabel = "Ausführlichkeit"
        #expect(withOption.optionID == "ausfuehrlichkeit")
        #expect(withOption.optionPlaceholder == "{{option:ausfuehrlichkeit}}")

        withOption.instructions += " " + withOption.optionPlaceholder
        #expect(!withOption.problems().contains(.optionNotUsed))
    }

    @Test
    func choicesAreSplitAndTrimmed() {
        var withOption = draft()
        withOption.optionLabel = "Ton"
        withOption.optionChoices = " knapp ,normal,  ausführlich , "
        #expect(withOption.choices == ["knapp", "normal", "ausführlich"])
    }

    // MARK: - Das fertige Werkzeug

    @Test
    func theToolCarriesEverythingFromTheDraft() {
        var full = draft()
        full.subtitle = "Aus einem Diff eine Notiz"
        full.systemImage = "text.badge.plus"
        full.keywords = "diff, notiz"
        full.inputPlaceholder = "Diff einfügen …"
        full.temperature = 0.2
        full.optionLabel = "Ton"
        full.optionChoices = "sachlich, locker"
        full.instructions += " " + full.optionPlaceholder

        let tool = full.makeTool()
        #expect(tool.id == "user.aenderungstext-schreiben")
        #expect(tool.title == "Änderungstext schreiben")
        #expect(tool.systemImage == "text.badge.plus")
        #expect(tool.keywords == ["diff", "notiz"])
        #expect(tool.temperature == 0.2)
        #expect(tool.categoryID == ToolCategory.custom.id)
        // Ohne den Platzhalter für die Eingabe käme beim Modell nichts an.
        #expect(tool.promptTemplate.contains("{{input}}"))
        #expect(tool.options.count == 1)
        #expect(tool.options[0].id == "ton")
        #expect(tool.options[0].defaultValue == "sachlich")
    }

    @Test
    func withoutAnOptionTheToolHasNone() {
        #expect(draft().makeTool().options.isEmpty)
    }

    /// Die Datei ist zugleich die Anleitung für die nächste von Hand.
    @Test
    func theJSONIsReadableAndComplete() {
        let text = draft().json()
        #expect(text.contains("\"id\" : \"user.aenderungstext-schreiben\""))
        #expect(text.contains("{{input}}"))
        // Schrägstriche bleiben Schrägstriche.
        #expect(!text.contains("\\/"))
    }

    /// Was geschrieben wurde, muss der Lader auch wieder einlesen können —
    /// sonst entsteht eine Datei, die beim nächsten Start still scheitert.
    @Test
    func whatIsWrittenCanBeReadBackAsATool() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "anvil-eigenes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }

        var full = draft()
        full.optionLabel = "Ton"
        full.optionChoices = "sachlich, locker"
        full.instructions += " " + full.optionPlaceholder

        let url = try full.write(to: folder)
        #expect(url.lastPathComponent == "aenderungstext-schreiben.json")

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(AIPromptTool.self, from: data)
        #expect(decoded.id == full.identifier)
        #expect(decoded.options.count == 1)
        #expect(decoded.instructions.contains(full.optionPlaceholder))
    }
}
