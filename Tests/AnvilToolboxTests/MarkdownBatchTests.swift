import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Markdown im Stapel")
struct MarkdownBatchTests {
    private let readme = """
    # Anvil

    Siehe [den Aufbau](aufbau.md) und [den Kern](aufbau.md#der-kern).
    """

    private let aufbau = """
    # Aufbau

    ## Der Kern

    Zurück zum [README](README.md).
    """

    @Test
    func everyFileIsMeasuredOnItsOwn() {
        let batch = MarkdownBatch([("README.md", readme), ("aufbau.md", aufbau)])
        #expect(batch.entries.count == 2)
        #expect(batch.entries[0].name == "README.md")
        #expect(batch.entries[0].document.headings.count == 1)
        #expect(batch.entries[1].document.headings.count == 2)
        #expect(batch.wordCount > 0)
    }

    /// Das, was eine Einzelansicht prinzipiell nicht kann.
    @Test
    func aLinkToAFileThatIsNotThereIsReported() {
        let batch = MarkdownBatch([
            ("README.md", "Siehe [weg](geloescht.md)."),
            ("aufbau.md", aufbau)
        ])
        let problems = batch.entries[0].crossProblems
        #expect(problems.count == 1)
        #expect(problems[0].kind == .missingFile)
        #expect(problems[0].target == "geloescht.md")
    }

    /// Eine Datei wird umbenannt, eine Überschrift umformuliert — und die
    /// Verweise darauf zeigen ins Leere, ohne dass etwas rot wird.
    @Test
    func anAnchorInAnotherFileIsCheckedToo() {
        let batch = MarkdownBatch([
            ("README.md", "Siehe [den Kern](aufbau.md#gibt-es-nicht)."),
            ("aufbau.md", aufbau)
        ])
        let problems = batch.entries[0].crossProblems
        #expect(problems.count == 1)
        #expect(problems[0].kind == .missingAnchor)
    }

    @Test
    func whatIsThereIsNotReported() {
        let batch = MarkdownBatch([("README.md", readme), ("aufbau.md", aufbau)])
        #expect(batch.entries.allSatisfy { $0.crossProblems.isEmpty })
    }

    /// Ein Verweis nach vorn ist so gültig wie einer nach hinten — deshalb
    /// werden erst alle Anker gesammelt und dann geprüft.
    @Test
    func theOrderOfTheFilesDoesNotMatter() {
        let forwards = MarkdownBatch([("README.md", readme), ("aufbau.md", aufbau)])
        let backwards = MarkdownBatch([("aufbau.md", aufbau), ("README.md", readme)])
        #expect(forwards.problemCount == backwards.problemCount)
    }

    /// Adressen im Netz, Bilder und Sprungmarken im eigenen Dokument gehen
    /// den Stapel nichts an.
    @Test
    func onlyLinksToMarkdownFilesAreChecked() {
        let batch = MarkdownBatch([
            ("a.md", """
            # A

            [nach draußen](https://example.com/x.md)
            ![Bild](bild.png)
            [im Dokument](#a)
            [kein Markdown](daten.csv)
            """)
        ])
        #expect(batch.entries[0].crossProblems.isEmpty)
    }

    /// Der Stapel kennt keine Ordnerstruktur — verglichen wird der Dateiname.
    @Test
    func aRelativePathIsMatchedByItsFileName() {
        let batch = MarkdownBatch([
            ("README.md", "Siehe [dort](../docs/aufbau.md#der-kern)."),
            ("aufbau.md", aufbau)
        ])
        #expect(batch.entries[0].crossProblems.isEmpty)
    }

    @Test
    func problemsInsideAFileCountToo() {
        let batch = MarkdownBatch([
            ("a.md", "## Zwei\n\n#### Vier"),
            ("b.md", "# Sauber")
        ])
        #expect(batch.entries[0].problemCount > 0)
        #expect(batch.entries[1].problemCount == 0)
        #expect(batch.problemCount == batch.entries[0].problemCount)
    }

    @Test
    func theReportHasAHeaderAndOneLinePerFile() {
        let batch = MarkdownBatch([("README.md", readme), ("aufbau.md", aufbau)])
        let lines = batch.report.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 3)
        #expect(lines[0].split(separator: "\t").count == 5)
        #expect(lines[1].hasPrefix("README.md\t"))
    }

    @Test
    func theProblemReportNamesTheFileAndTheLine() {
        let batch = MarkdownBatch([
            ("README.md", "Siehe [weg](geloescht.md)."),
            ("aufbau.md", aufbau)
        ])
        #expect(batch.problemReport.contains("README.md\t1\t"))
        #expect(batch.problemReport.contains("geloescht.md"))
    }

    @Test
    func nothingInIsAnEmptyBatch() {
        let batch = MarkdownBatch([])
        #expect(batch.isEmpty)
        #expect(batch.problemCount == 0)
        #expect(batch.wordCount == 0)
        #expect(batch.problemReport.isEmpty)
    }
}
