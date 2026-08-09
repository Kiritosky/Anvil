import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("CSV lesen")
struct CSVParsingTests {
    private func table(_ text: String, _ delimiter: CSVTable.Delimiter = .comma) -> CSVTable {
        CSVTable(parsing: text, delimiter: delimiter, hasHeader: true)
    }

    @Test
    func aPlainTableIsHeaderPlusRows() {
        let result = table("Name,Ort\nAnna,Bremen\nBen,Kiel")
        #expect(result.header == ["Name", "Ort"])
        #expect(result.rows == [["Anna", "Bremen"], ["Ben", "Kiel"]])
        #expect(result.rowCount == 2)
        #expect(result.columnCount == 2)
    }

    /// Der Grund, warum hier ein Zustandsautomat steht und kein `split`.
    @Test
    func aQuotedFieldMayContainTheSeparator() {
        let result = table("Name,Notiz\nAnna,\"Bremen, Nord\"")
        #expect(result.rows == [["Anna", "Bremen, Nord"]])
    }

    @Test
    func aQuotedFieldMayContainNewlines() {
        let result = table("Name,Notiz\nAnna,\"erste Zeile\nzweite Zeile\"")
        #expect(result.rowCount == 1)
        #expect(result.rows[0][1] == "erste Zeile\nzweite Zeile")
    }

    @Test
    func doubledQuotesAreOneQuote() {
        let result = table("Name,Zitat\nAnna,\"sagt \"\"hallo\"\" laut\"")
        #expect(result.rows[0][1] == "sagt \"hallo\" laut")
    }

    @Test
    func anEmptyQuotedFieldStaysEmpty() {
        let result = table("a,b,c\n1,\"\",3")
        #expect(result.rows == [["1", "", "3"]])
    }

    @Test
    func windowsLineEndingsAreOneBreakAndNotTwo() {
        let result = table("Name,Ort\r\nAnna,Bremen\r\nBen,Kiel\r\n")
        #expect(result.rowCount == 2)
        #expect(result.rows[1] == ["Ben", "Kiel"])
    }

    /// Eine kaputte Zeile darf die anderen Spalten nicht mitnehmen.
    @Test
    func shortRowsArePaddedRatherThanDropped() {
        let result = table("a,b,c\n1,2\n4,5,6")
        #expect(result.rowCount == 2)
        #expect(result.rows[0] == ["1", "2", ""])
    }

    /// Steht in einer Zeile eine Spalte zu viel, wächst die Tabelle mit — auch
    /// die Kopfzeile, sonst fiele die letzte Spalte lautlos weg.
    @Test
    func anExtraColumnWidensTheWholeTable() {
        let result = table("a,b\n1,2,3")
        #expect(result.columnCount == 3)
        #expect(result.header == ["a", "b", CSVTable.columnName(2)])
        #expect(result.rows[0] == ["1", "2", "3"])
    }

    @Test
    func blankLinesInTheMiddleDoNotBecomeRows() {
        let result = table("a,b\n1,2\n\n3,4\n\n")
        #expect(result.rowCount == 2)
    }

    @Test
    func withoutAHeaderTheColumnsAreNumbered() {
        let result = CSVTable(parsing: "1,2\n3,4", delimiter: .comma, hasHeader: false)
        #expect(result.rowCount == 2)
        #expect(result.header == [CSVTable.columnName(0), CSVTable.columnName(1)])
        #expect(!result.hasNamedColumns)
    }

    @Test
    func anEmptyHeaderCellGetsANumber() {
        let result = table("Name,,Ort\nAnna,x,Bremen")
        #expect(result.header == ["Name", CSVTable.columnName(1), "Ort"])
    }

    @Test
    func nothingInIsNothingOut() {
        #expect(table("").isEmpty)
        #expect(table("\n\n").isEmpty)
        #expect(CSVTable.empty.isEmpty)
    }
}

@Suite("Trennzeichen raten")
struct CSVDelimiterTests {
    @Test
    func aSemicolonExportIsRecognised() {
        #expect(CSVTable.detectDelimiter(in: "a;b;c\n1;2;3") == .semicolon)
    }

    @Test
    func tabsWin() {
        #expect(CSVTable.detectDelimiter(in: "a\tb\n1\t2") == .tab)
    }

    /// Der eigentliche Fall: Kommas kommen häufiger vor, aber ungleichmäßig —
    /// das Semikolon steht in jeder Zeile gleich oft.
    @Test
    func consistencyBeatsFrequency() {
        let text = """
        Name;Notiz
        Anna;kurz, knapp, klar
        Ben;lang, ausführlich, umständlich
        """
        #expect(CSVTable.detectDelimiter(in: text) == .semicolon)
    }

    @Test
    func aTextWithoutAnyTableFallsBackToComma() {
        #expect(CSVTable.detectDelimiter(in: "einfach nur ein Satz") == .comma)
        #expect(CSVTable.detectDelimiter(in: "") == .comma)
    }
}

@Suite("CSV umformen")
struct CSVTransformTests {
    private let sample = CSVTable(
        parsing: "Name,Ort,Umsatz\nBen,Kiel,980\nAnna,Bremen,1200\nCem,Aachen,10",
        delimiter: .comma,
        hasHeader: true
    )

    @Test
    func textSortsAlphabeticallyAndBackwards() {
        #expect(sample.sorted(by: 0).rows.map { $0[0] } == ["Anna", "Ben", "Cem"])
        #expect(sample.sorted(by: 0, ascending: false).rows.map { $0[0] } == ["Cem", "Ben", "Anna"])
    }

    /// Textsortierung stellte 10 vor 980 — genau der Fehler, an dem man einer
    /// Tabelle nicht mehr traut.
    @Test
    func numbersSortAsNumbers() {
        #expect(sample.sorted(by: 2).rows.map { $0[2] } == ["10", "980", "1200"])
    }

    @Test
    func sortingAnUnknownColumnChangesNothing() {
        #expect(sample.sorted(by: 9).rows == sample.rows)
        #expect(sample.sorted(by: -1).rows == sample.rows)
    }

    @Test
    func filteringLooksInEveryColumnAndIgnoresCase() {
        // Kleingeschrieben, und trifft trotzdem die Spalte „Ort".
        #expect(sample.filtered(by: "kiel").rowCount == 1)
        // Auch in einer Zahlenspalte wird gesucht.
        #expect(sample.filtered(by: "1200").rowCount == 1)
        #expect(sample.filtered(by: "n").rowCount == 3)
        // Ein leerer Filter filtert nicht, statt alles wegzunehmen.
        #expect(sample.filtered(by: "   ").rowCount == 3)
        #expect(sample.filtered(by: "Hamburg").rowCount == 0)
    }

    @Test
    func selectingKeepsTheGivenOrder() {
        let picked = sample.selecting([2, 0])
        #expect(picked.header == ["Umsatz", "Name"])
        #expect(picked.rows[0] == ["980", "Ben"])
    }
}

@Suite("CSV ausgeben")
struct CSVOutputTests {
    private let sample = CSVTable(
        parsing: "Name,Notiz,Umsatz\nAnna,\"Bremen, Nord\",1200\nBen,,980",
        delimiter: .comma,
        hasHeader: true
    )

    /// Angeführt wird nur, was es braucht — sonst wäre der Export zwar richtig
    /// und trotzdem unlesbar.
    @Test
    func onlyFieldsThatNeedQuotesGetThem() {
        let text = sample.text(delimiter: .comma)
        #expect(text.contains("Anna,\"Bremen, Nord\",1200"))
        #expect(text.contains("Ben,,980"))
    }

    @Test
    func switchingToTabsDropsTheQuotesThatWereOnlyForTheComma() {
        let text = sample.text(delimiter: .tab)
        #expect(text.contains("Anna\tBremen, Nord\t1200"))
    }

    @Test
    func jsonKeepsTheColumnOrder() {
        let json = sample.json
        #expect(json.hasPrefix("[\n  {\n"))
        let name = json.range(of: "\"Name\"")
        let umsatz = json.range(of: "\"Umsatz\"")
        #expect(name != nil)
        #expect(umsatz != nil)
        if let name, let umsatz { #expect(name.lowerBound < umsatz.lowerBound) }
        // Zahlen bleiben Zahlen, leere Felder werden null.
        #expect(json.contains("\"Umsatz\": 1200"))
        #expect(json.contains("\"Notiz\": null"))
    }

    @Test
    func jsonIsValidJSON() throws {
        let data = try #require(sample.json.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(parsed?.count == 2)
        #expect(parsed?[0]["Notiz"] as? String == "Bremen, Nord")
    }

    /// `Double` liest `0x1p3`, `inf` und `.5` als Zahlen — JSON tut das nicht.
    @Test(arguments: [
        ("1200", true), ("-3", true), ("1.5", true), ("1e5", true),
        ("0", true), ("0.5", true), ("-0.5", true),
        ("0x1p3", false), ("inf", false), ("nan", false), (".5", false),
        // Eine Artikelnummer ist keine Zahl: unangeführt käme sie als 123
        // wieder heraus.
        ("00123", false),
        ("1,5", false), ("1.2.3", false), ("", false)
    ])
    func onlyRealJSONNumbersStayUnquoted(_ text: String, _ expected: Bool) {
        #expect(CSVTable.isJSONNumber(text) == expected)
    }

    @Test
    func markdownEscapesThePipeItUsesItself() {
        let table = CSVTable(parsing: "a,b\n1,x|y", delimiter: .comma, hasHeader: true)
        let markdown = table.markdown
        #expect(markdown.contains("| a | b |"))
        #expect(markdown.contains("| --- | --- |"))
        #expect(markdown.contains("| 1 | x\\|y |"))
    }

    @Test
    func sqlQuotesTextAndLeavesNumbersAlone() {
        // Umlaute bleiben — sie sind Buchstaben, und Postgres wie SQLite
        // nehmen sie unangeführt an. Ersetzt wird nur, was kein Zeichen für
        // einen Bezeichner ist.
        let statements = sample.sql(table: "Umsätze 2026")
        #expect(statements.contains("INSERT INTO umsätze_2026"))
        #expect(statements.contains("VALUES ('Anna', 'Bremen, Nord', 1200);"))
        #expect(statements.contains("VALUES ('Ben', NULL, 980);"))
    }

    @Test
    func sqlDoublesTheApostropheThatWouldEndTheString() {
        let table = CSVTable(parsing: "a\nO'Brien", delimiter: .comma, hasHeader: true)
        #expect(table.sql(table: "t").contains("VALUES ('O''Brien');"))
    }

    @Test
    func anIdentifierNeverStartsWithADigit() {
        #expect(CSVTable.sqlIdentifier("2026 Umsatz") == "_2026_umsatz")
        #expect(CSVTable.sqlIdentifier("Name") == "name")
    }
}

@Suite("Spalten verstehen")
struct CSVSummaryTests {
    @Test
    func aNumericColumnKnowsItsRange() {
        let table = CSVTable(
            parsing: "Umsatz\n10\n980\n1200",
            delimiter: .comma,
            hasHeader: true
        )
        let summary = table.summary(of: 0)
        #expect(summary.isNumeric)
        #expect(summary.minimum == 10)
        #expect(summary.maximum == 1200)
        #expect(summary.sum == 2190)
        #expect(summary.mean == 730)
    }

    /// Eine Spalte mit einem „k. A." dazwischen ist keine Zahlenspalte — sonst
    /// rechnete das Werkzeug über einen Teil der Daten und sagte es nicht.
    @Test
    func oneWordAmongTheNumbersMakesTheColumnText() {
        let table = CSVTable(
            parsing: "Umsatz\n10\nk. A.\n1200",
            delimiter: .comma,
            hasHeader: true
        )
        #expect(!table.summary(of: 0).isNumeric)
    }

    /// Eine leere Zelle ist etwas anderes als eine leere Zeile — die Zeile
    /// fällt weg, die Zelle wird gezählt.
    @Test
    func emptyCellsAreCountedAndDoNotSpoilTheNumbers() {
        let table = CSVTable(
            parsing: "Umsatz,Ort\n10,Kiel\n,Bremen\n1200,Aachen",
            delimiter: .comma,
            hasHeader: true
        )
        let summary = table.summary(of: 0)
        #expect(summary.isNumeric)
        #expect(summary.filled == 2)
        #expect(summary.empty == 1)
        #expect(summary.sum == 1210)
    }

    @Test
    func distinctCountsWhatIsActuallyDifferent() {
        let table = CSVTable(
            parsing: "Ort\nKiel\nKiel\nBremen",
            delimiter: .comma,
            hasHeader: true
        )
        #expect(table.summary(of: 0).distinct == 2)
    }
}

@Suite("Zahlen in Tabellen")
struct CSVNumberTests {
    /// Deutsche und englische Exporte landen im selben Werkzeug. Entschieden
    /// wird nach dem Trennzeichen, das zuletzt kommt.
    @Test(arguments: [
        ("1234", 1234.0),
        ("1234.56", 1234.56),
        ("1.234,56", 1234.56),
        ("1,234.56", 1234.56),
        ("1,5", 1.5),
        ("-42", -42.0),
        ("1\u{202F}234", 1234.0),
        ("  7  ", 7.0)
    ])
    func numbersAreReadTheWayTheyWereWritten(_ text: String, _ expected: Double) {
        #expect(CSVTable.number(text) == expected)
    }

    @Test(arguments: ["", "k. A.", "1.2.3,4,5", "Kiel"])
    func whatIsNotANumberStaysNil(_ text: String) {
        #expect(CSVTable.number(text) == nil)
    }
}
