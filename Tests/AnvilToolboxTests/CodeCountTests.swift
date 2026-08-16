import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Sprachen erkennen")
struct CodeLanguageTests {
    @Test
    func theExtensionDecides() throws {
        #expect(CodeLanguage.of(path: "Sources/App/Main.swift")?.name == "Swift")
        #expect(CodeLanguage.of(path: "app/index.tsx")?.name == "TypeScript")
        #expect(CodeLanguage.of(path: "script.py")?.name == "Python")
        #expect(CodeLanguage.of(path: "style.scss")?.name == "Sass")
    }

    /// Manche Dateien haben keine Endung und trotzdem eine Sprache.
    @Test
    func someFilesAreKnownByName() {
        #expect(CodeLanguage.of(path: "Makefile")?.name == "Make")
        #expect(CodeLanguage.of(path: "docker/Dockerfile")?.name == "Dockerfile")
    }

    /// Was Anvil nicht kennt, wird nicht geraten — eine Zeile
    /// „Sonstiges: 412.000" macht die ganze Zahl wertlos.
    @Test
    func whatIsUnknownStaysUnknown() {
        #expect(CodeLanguage.of(path: "bild.png") == nil)
        #expect(CodeLanguage.of(path: "daten.sqlite") == nil)
        #expect(CodeLanguage.of(path: "LICENSE") == nil)
        #expect(CodeLanguage.of(path: ".gitignore") == nil)
    }

    @Test
    func borrowedCodeIsLeftOut() {
        #expect(CodeLanguage.isIgnored("node_modules/react/index.js"))
        #expect(CodeLanguage.isIgnored("app/Pods/Alamofire/Source.swift"))
        #expect(CodeLanguage.isIgnored("web/dist/bundle.js"))
        #expect(!CodeLanguage.isIgnored("Sources/App/Main.swift"))
    }

    /// Der Ordnername zählt, nicht der Dateiname: Eine Datei namens
    /// `build.swift` liegt nicht in `build`.
    @Test
    func onlyFoldersCount() {
        #expect(!CodeLanguage.isIgnored("Sources/build.swift"))
        #expect(CodeLanguage.isIgnored("build/Sources/main.swift"))
    }
}

@Suite("Codezeilen zählen")
struct CodeCountTests {
    private func file(_ path: String, _ text: String) -> CodeCount.SourceFile {
        CodeCount.SourceFile(path: path, text: text)
    }

    @Test
    func codeCommentAndBlankAreToldApart() throws {
        let count = CodeCount.count([
            file("a.swift", """
                // Ein Kommentar
                let x = 1

                let y = 2
                """)
        ])

        let entry = try #require(count.entries.first)
        #expect(entry.language == "Swift")
        #expect(entry.code == 2)
        #expect(entry.comments == 1)
        #expect(entry.blanks == 1)
        #expect(entry.lines == 4)
    }

    @Test
    func aBlockCommentCountsUntilItCloses() throws {
        let count = CodeCount.count([
            file("a.swift", """
                /*
                 Zwei Zeilen Erklärung
                 */
                let x = 1
                """)
        ])

        let entry = try #require(count.entries.first)
        #expect(entry.comments == 3)
        #expect(entry.code == 1)
    }

    /// Ein Block, der in derselben Zeile wieder zugeht, macht die nächste
    /// nicht zum Kommentar.
    @Test
    func aBlockThatClosesOnTheSameLineEndsThere() throws {
        let count = CodeCount.count([
            file("a.swift", """
                /* kurz */
                let x = 1
                let y = 2
                """)
        ])

        let entry = try #require(count.entries.first)
        #expect(entry.comments == 1)
        #expect(entry.code == 2)
    }

    @Test
    func everyLanguageBringsItsOwnCommentMarker() throws {
        let count = CodeCount.count([
            file("a.py", "# Kommentar\nprint(1)"),
            file("a.lua", "-- Kommentar\nlocal x = 1"),
            file("a.html", "<!-- Kommentar -->\n<p>Text</p>")
        ])

        for entry in count.entries {
            #expect(entry.comments == 1)
            #expect(entry.code == 1)
        }
    }

    @Test
    func filesOfTheSameLanguageAreAddedUp() throws {
        let count = CodeCount.count([
            file("a.swift", "let x = 1"),
            file("b.swift", "let y = 2\nlet z = 3")
        ])

        let entry = try #require(count.entries.first)
        #expect(entry.files == 2)
        #expect(entry.code == 3)
    }

    /// Die größte Sprache steht oben — danach fragt, wer wissen will, woraus
    /// ein Projekt besteht.
    @Test
    func theBiggestLanguageComesFirst() {
        let count = CodeCount.count([
            file("a.py", "print(1)"),
            file("a.swift", "let a = 1\nlet b = 2\nlet c = 3")
        ])
        #expect(count.entries.map(\.language) == ["Swift", "Python"])
    }

    @Test
    func whatIsNotCodeIsCountedAsSkipped() {
        let count = CodeCount.count([
            file("bild.png", "nicht wirklich"),
            file("node_modules/react/index.js", "const x = 1"),
            file("a.swift", "let x = 1")
        ])
        #expect(count.skipped == 2)
        #expect(count.entries.count == 1)
    }

    /// Der Anteil hängt am Code, nicht an allen Zeilen: Ein Diagramm, in dem
    /// eine Sprache groß aussieht, weil dort großzügig Absätze gesetzt
    /// werden, beantwortet die Frage nicht.
    @Test
    func theShareIsMeasuredInCode() throws {
        let count = CodeCount.count([
            file("a.swift", "let a = 1\nlet b = 2\nlet c = 3"),
            file("a.py", "print(1)\n\n\n\n\n\n\n\n\n")
        ])

        let swift = try #require(count.entries.first { $0.language == "Swift" })
        let python = try #require(count.entries.first { $0.language == "Python" })
        #expect(count.share(of: swift) == 0.75)
        #expect(count.share(of: python) == 0.25)
    }

    @Test
    func theCommentShareIgnoresBlankLines() throws {
        let count = CodeCount.count([
            file("a.swift", "// eins\nlet x = 1\n\n\n")
        ])
        let entry = try #require(count.entries.first)
        #expect(entry.commentShare == 0.5)
    }

    @Test
    func theTotalsAddUp() {
        let count = CodeCount.count([
            file("a.swift", "// eins\nlet x = 1"),
            file("a.py", "print(1)\n")
        ])
        #expect(count.totalCode == 2)
        #expect(count.totalComments == 1)
        #expect(count.fileCount == 2)
        #expect(count.totalLines == count.totalCode + count.totalComments + count.totalBlanks)
    }

    @Test
    func anEmptyFileHasNoLines() {
        let count = CodeCount.count([file("a.swift", "")])
        #expect(count.entries.first?.lines == 0)
    }

    @Test
    func nothingInIsAnEmptyCount() {
        #expect(CodeCount.count([]).isEmpty)
        #expect(CodeCount.empty.totalLines == 0)
        #expect(CodeCount.empty.report.components(separatedBy: "\n").count == 2)
    }

    // MARK: - Ausgeben

    @Test
    func theReportHasALinePerLanguageAndASum() {
        let count = CodeCount.count([
            file("a.swift", "let x = 1"),
            file("a.py", "print(1)")
        ])
        let lines = count.report.components(separatedBy: "\n")
        #expect(lines.count == count.entries.count + 2)
        #expect(lines.allSatisfy {
            $0.components(separatedBy: "\t").count == CodeCount.reportColumns.count
        })
        #expect(count.rows().allSatisfy { $0.count == CodeCount.reportColumns.count })
    }

    @Test
    func percentagesAreWhole() {
        #expect(CodeCount.percent(0) == "0 %")
        #expect(CodeCount.percent(1) == "100 %")
        #expect(CodeCount.percent(0.333) == "33 %")
    }
}
