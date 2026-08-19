import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Markdown gliedern")
struct MarkdownOutlineTests {
    @Test
    func bothHeadingStylesAreFound() {
        let document = MarkdownDocument("""
        # Eins

        Titel
        =====

        ## Zwei

        Unterzeile
        ----------
        """)
        #expect(document.headings.map(\.level) == [1, 1, 2, 2])
        #expect(document.headings.map(\.text) == ["Eins", "Titel", "Zwei", "Unterzeile"])
    }

    /// Der Grund, warum Codeblöcke überhaupt verfolgt werden: ein Kommentar in
    /// einem Shell-Beispiel ist keine Überschrift.
    @Test
    func hashesInsideCodeBlocksAreNotHeadings() {
        let document = MarkdownDocument("""
        # Echt

        ```sh
        # nur ein Kommentar
        echo hallo
        ```

        ## Auch echt
        """)
        #expect(document.headings.map(\.text) == ["Echt", "Auch echt"])
    }

    @Test
    func aHashWithoutASpaceIsATagAndNotATitle() {
        #expect(MarkdownDocument("#kein Titel").headings.isEmpty)
        #expect(MarkdownDocument("####### zu tief").headings.isEmpty)
        #expect(MarkdownDocument("###").headings.isEmpty)
    }

    @Test
    func closingHashesAreDropped() {
        #expect(MarkdownDocument("## Titel ##").headings.first?.text == "Titel")
    }

    @Test
    func anchorsFollowTheGitHubRules() {
        #expect(MarkdownDocument.anchor(for: "Was jetzt?") == "was-jetzt")
        #expect(MarkdownDocument.anchor(for: "Netz & Adressen") == "netz--adressen")
        #expect(MarkdownDocument.anchor(for: "Größe") == "größe")
        #expect(MarkdownDocument.anchor(for: "snake_case") == "snake-case")
    }

    /// Zwei gleich benannte Abschnitte bekämen sonst denselben Anker, und der
    /// zweite Link führte auf den ersten.
    @Test
    func repeatedHeadingsGetNumberedAnchors() {
        let document = MarkdownDocument("## Aufbau\n\n## Aufbau\n\n## Aufbau")
        #expect(document.headings.map(\.anchor) == ["aufbau", "aufbau-1", "aufbau-2"])
    }

    /// Ein Dokument, das bei H2 anfängt, soll nicht schon beim ersten Eintrag
    /// eingerückt sein.
    @Test
    func theTableOfContentsIndentsRelatively() {
        let document = MarkdownDocument("## Oben\n\n### Darunter")
        #expect(document.tableOfContents == "- [Oben](#oben)\n  - [Darunter](#darunter)")
    }

    @Test
    func nothingInIsNoTableOfContents() {
        #expect(MarkdownDocument("").tableOfContents.isEmpty)
        #expect(MarkdownDocument("nur Text").tableOfContents.isEmpty)
    }
}

@Suite("Markdown-Verweise")
struct MarkdownLinkTests {
    private let document = MarkdownDocument("""
    Ein [Link](https://example.com) und ein ![Bild](bild.png).

    Ein [Sprung](#irgendwohin) im Dokument.

    ```
    [nicht gezählt](weil-code)
    ```
    """)

    @Test
    func linksAndImagesAreToldApart() {
        #expect(document.links.count == 3)
        #expect(document.links.filter(\.isImage).count == 1)
        #expect(document.links[0].target == "https://example.com")
        #expect(document.links[1].target == "bild.png")
    }

    @Test
    func linksInsideCodeBlocksAreNotLinks() {
        #expect(!document.links.contains { $0.target == "weil-code" })
    }

    @Test
    func aLinkKnowsWhereItPoints() {
        #expect(document.links[0].isExternal)
        #expect(!document.links[1].isExternal)
        #expect(document.links[2].isAnchor)
    }

    /// `[Text](ziel "Titel")` — der Titel gehört nicht zum Ziel.
    @Test
    func aTitleBehindTheTargetIsNotPartOfIt() {
        let document = MarkdownDocument("[Da](https://example.com \"Ein Titel\")")
        #expect(document.links.first?.target == "https://example.com")
    }
}

@Suite("Markdown prüfen")
struct MarkdownProblemTests {
    @Test
    func aSkippedLevelIsReported() {
        let document = MarkdownDocument("## Zwei\n\n#### Vier")
        #expect(document.problems.contains { $0.kind == .skippedLevel })
    }

    @Test
    func goingBackUpIsFine() {
        let document = MarkdownDocument("# Eins\n\n## Zwei\n\n### Drei\n\n# Wieder eins")
        #expect(document.problems.isEmpty)
    }

    @Test
    func aRepeatedHeadingIsReported() {
        let document = MarkdownDocument("## Aufbau\n\n## Aufbau")
        #expect(document.problems.contains { $0.kind == .duplicateAnchor })
    }

    @Test
    func anAnchorWithoutAHeadingIsReported() {
        let document = MarkdownDocument("# Da\n\n[hin](#gibt-es-nicht)")
        #expect(document.problems.contains { $0.kind == .brokenAnchor })
    }

    @Test
    func anAnchorThatExistsIsNotReported() {
        let document = MarkdownDocument("# Da hin\n\n[dahin](#da-hin)")
        #expect(!document.problems.contains { $0.kind == .brokenAnchor })
    }

    @Test
    func anEmptyTargetIsReported() {
        let document = MarkdownDocument("[nirgendwohin]()")
        #expect(document.problems.contains { $0.kind == .emptyTarget })
    }

    @Test
    func anOpenCodeBlockIsReported() {
        let document = MarkdownDocument("```sh\necho hallo\n")
        #expect(document.problems.contains { $0.kind == .unclosedFence })
    }

    @Test
    func aClosedCodeBlockIsNotReported() {
        let document = MarkdownDocument("```sh\necho hallo\n```\n")
        #expect(!document.problems.contains { $0.kind == .unclosedFence })
    }
}

@Suite("Markdown zählen")
struct MarkdownStatisticsTests {
    @Test
    func codeDoesNotCountAsProse() {
        let plain = MarkdownDocument("ein zwei drei").statistics
        #expect(plain.words == 3)

        let withCode = MarkdownDocument("ein zwei drei\n\n```\nvier fünf sechs sieben\n```").statistics
        #expect(withCode.words == 3)
        #expect(withCode.codeBlocks == 1)
    }

    @Test
    func readingTimeIsNeverZero() {
        #expect(MarkdownDocument("eins").statistics.readingMinutes == 1)
        let long = Array(repeating: "wort", count: 400).joined(separator: " ")
        #expect(MarkdownDocument(long).statistics.readingMinutes == 2)
    }

    @Test
    func tasksAreCountedOpenAndDone() {
        let document = MarkdownDocument("""
        - [x] fertig
        - [ ] offen
        - [ ] auch offen
        - kein Haken
        """)
        #expect(document.statistics.tasksDone == 1)
        #expect(document.statistics.tasksOpen == 2)
    }

    @Test
    func paragraphsAreSeparatedByBlankLines() {
        let document = MarkdownDocument("eins\nnoch eins\n\nzwei\n\n\ndrei")
        #expect(document.statistics.paragraphs == 3)
    }
}

@Suite("Markdown nach HTML")
struct MarkdownHTMLTests {
    @Test
    func headingsCarryTheirAnchor() {
        #expect(MarkdownDocument("## Was jetzt?").html == "<h2 id=\"was-jetzt\">Was jetzt?</h2>")
    }

    @Test
    func emphasisIsRecognisedInTheRightOrder() {
        #expect(MarkdownDocument("**fett**").html == "<p><strong>fett</strong></p>")
        #expect(MarkdownDocument("*kursiv*").html == "<p><em>kursiv</em></p>")
        #expect(MarkdownDocument("~~weg~~").html == "<p><del>weg</del></p>")
    }

    /// Ein Unterstrich mitten in einem Bezeichner ist keine Auszeichnung.
    @Test
    func underscoresInsideAnIdentifierStay() {
        #expect(MarkdownDocument("max_size_limit").html == "<p>max_size_limit</p>")
        #expect(MarkdownDocument("_kursiv_").html == "<p><em>kursiv</em></p>")
    }

    /// Der Fall, an dem ein Werkzeug unbrauchbar wird, wenn es ihn falsch
    /// macht: was in einem Code-Schnipsel steht, wird nicht ausgelegt.
    @Test
    func markupInsideACodeSpanIsLeftAlone() {
        #expect(MarkdownDocument("`**nicht fett**`").html == "<p><code>**nicht fett**</code></p>")
    }

    @Test
    func htmlInTheSourceIsEscapedAndNotPassedThrough() {
        #expect(MarkdownDocument("<script>böse</script>").html
            == "<p>&lt;script&gt;böse&lt;/script&gt;</p>")
        #expect(MarkdownDocument("a & b").html == "<p>a &amp; b</p>")
    }

    @Test
    func codeBlocksKeepTheirLanguageAndTheirContent() {
        let html = MarkdownDocument("```swift\nlet a = 1 < 2\n```").html
        #expect(html == "<pre><code class=\"language-swift\">let a = 1 &lt; 2</code></pre>")
    }

    @Test
    func linksAndImagesBecomeTagsInTheRightOrder() {
        #expect(MarkdownDocument("[da](https://example.com)").html
            == "<p><a href=\"https://example.com\">da</a></p>")
        #expect(MarkdownDocument("![alt](bild.png)").html
            == "<p><img src=\"bild.png\" alt=\"alt\"></p>")
    }

    @Test
    func listsBecomeListsAndKnowTheirKind() {
        #expect(MarkdownDocument("- eins\n- zwei").html
            == "<ul>\n<li>eins</li>\n<li>zwei</li>\n</ul>")
        #expect(MarkdownDocument("1. eins\n2. zwei").html
            == "<ol>\n<li>eins</li>\n<li>zwei</li>\n</ol>")
    }

    @Test
    func taskListsBecomeCheckboxes() {
        let html = MarkdownDocument("- [x] fertig\n- [ ] offen").html
        #expect(html.contains("class=\"task-list\""))
        #expect(html.contains("<input type=\"checkbox\" disabled checked> fertig"))
        #expect(html.contains("<input type=\"checkbox\" disabled> offen"))
    }

    @Test
    func quotesAndRulesBecomeQuotesAndRules() {
        #expect(MarkdownDocument("> zitiert").html == "<blockquote><p>zitiert</p></blockquote>")
        #expect(MarkdownDocument("---").html == "<hr>")
        #expect(MarkdownDocument("***").html == "<hr>")
    }

    /// `---` unter einem Titel ist eine Überschrift, allein stehend eine
    /// Trennlinie. Genau diese Doppeldeutigkeit macht die Reihenfolge im
    /// Renderer aus.
    @Test
    func aRuleUnderATitleIsAHeading() {
        #expect(MarkdownDocument("Titel\n---").html == "<h2 id=\"titel\">Titel</h2>")
        #expect(MarkdownDocument("Text\n\n---").html == "<p>Text</p>\n<hr>")
    }

    @Test
    func tablesNeedTheirRuleLine() {
        let html = MarkdownDocument("| a | b |\n| --- | ---: |\n| 1 | 2 |").html
        #expect(html.contains("<th>a</th>"))
        #expect(html.contains("<th style=\"text-align:right\">b</th>"))
        #expect(html.contains("<td style=\"text-align:right\">2</td>"))

        #expect(MarkdownDocument("a | b").html == "<p>a | b</p>")
    }

    @Test
    func theWholePageCarriesTheFirstHeadingAsItsTitle() {
        let page = MarkdownDocument("# Bericht\n\nText").htmlPage()
        #expect(page.hasPrefix("<!DOCTYPE html>"))
        #expect(page.contains("<title>Bericht</title>"))
        #expect(page.contains("<h1 id=\"bericht\">Bericht</h1>"))
    }
}
