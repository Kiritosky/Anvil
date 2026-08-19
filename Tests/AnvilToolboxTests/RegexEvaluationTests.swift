import Foundation
import Testing

@testable import AnvilToolbox

@Suite("RegexEvaluation")
struct RegexEvaluationTests {
    private func evaluate(
        _ pattern: String,
        on subject: String,
        replacement: String = "",
        options: NSRegularExpression.Options = []
    ) throws -> RegexEvaluation {
        try RegexEvaluation(
            pattern: pattern,
            subject: subject,
            replacement: replacement,
            options: options
        )
    }

    @Test
    func findsEveryMatch() throws {
        let result = try evaluate("\\d+", on: "a1 bb22 c333")
        #expect(result.matches.map(\.text) == ["1", "22", "333"])
    }

    @Test
    func reportsWhereAMatchSits() throws {
        let result = try evaluate("welt", on: "hallo welt")
        let match = try #require(result.matches.first)
        #expect(match.location == 6)
        #expect(match.length == 4)
    }

    @Test
    func capturesGroupsInOrder() throws {
        let result = try evaluate("(\\w+)@(\\w+)", on: "post@beispiel")
        let match = try #require(result.matches.first)
        #expect(match.groups == ["post", "beispiel"])
    }

    @Test
    func reportsAnEmptyStringForGroupsThatDidNotMatch() throws {
        let result = try evaluate("(a)|(b)", on: "a")
        let match = try #require(result.matches.first)
        #expect(match.groups == ["a", ""])
    }

    @Test
    func honoursCaseInsensitivity() throws {
        #expect(try evaluate("hallo", on: "HALLO").matches.isEmpty)
        #expect(try evaluate("hallo", on: "HALLO", options: [.caseInsensitive]).matches.count == 1)
    }

    @Test
    func replacesUsingGroupTemplates() throws {
        let result = try evaluate("(\\w+) (\\w+)", on: "hallo welt", replacement: "$2 $1")
        #expect(result.replaced == "welt hallo")
    }

    @Test
    func leavesTheSubjectAloneWithoutAReplacement() throws {
        let result = try evaluate("\\d", on: "a1b2")
        #expect(result.replaced == "a1b2")
    }

    @Test
    func throwsOnABrokenPattern() {
        #expect(throws: (any Error).self) {
            try evaluate("(unbalanced", on: "irgendwas")
        }
    }

    @Test
    func handlesAnEmptySubject() throws {
        let result = try evaluate("\\d+", on: "")
        #expect(result.matches.isEmpty)
        #expect(result.replaced.isEmpty)
    }

    @Test
    func matchesUnicodeByCharacterNotByByte() throws {
        let result = try evaluate("Grüße", on: "Viele Grüße 👋")
        #expect(result.matches.first?.text == "Grüße")
    }
}
