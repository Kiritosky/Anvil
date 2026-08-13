import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Eine .env-Datei lesen")
struct EnvFileTests {
    @Test
    func keysAndValuesAreRead() throws {
        let file = EnvFile.read(
            """
            DATABASE_URL=postgres://localhost/anvil
            PORT=8080
            """,
            name: ".env"
        )

        #expect(file.entries.count == 2)
        #expect(file.value(of: "PORT") == "8080")
        #expect(file.entries.first?.line == 1)
    }

    @Test
    func commentsAndBlankLinesAreSkipped() {
        let file = EnvFile.read(
            """
            # Zugang zur Datenbank
            DATABASE_URL=postgres://localhost/anvil

              # eingerückter Kommentar
            PORT=8080
            """,
            name: ".env"
        )

        #expect(file.keys == ["DATABASE_URL", "PORT"])
        #expect(file.problems.isEmpty)
    }

    @Test
    func exportInFrontIsAllowed() {
        let file = EnvFile.read("export TOKEN=abc", name: ".env")
        #expect(file.value(of: "TOKEN") == "abc")
    }

    @Test
    func spacesAroundTheEqualsSignAreIgnored() {
        let file = EnvFile.read("PORT = 8080", name: ".env")
        #expect(file.value(of: "PORT") == "8080")
    }

    @Test
    func emptyValuesStayEmpty() throws {
        let file = EnvFile.read("TOKEN=", name: ".env")
        let entry = try #require(file.entries.first)
        #expect(entry.isEmpty)
        #expect(entry.value.isEmpty)
    }

    // MARK: - Anführungszeichen

    @Test
    func quotesAreRemoved() {
        let file = EnvFile.read(
            """
            EINS="mit Leerzeichen"
            ZWEI='auch so'
            """,
            name: ".env"
        )
        #expect(file.value(of: "EINS") == "mit Leerzeichen")
        #expect(file.value(of: "ZWEI") == "auch so")
    }

    /// Ein Passwort mit `#` darin verlöre sonst seine zweite Hälfte.
    @Test
    func aHashInsideQuotesIsPartOfTheValue() {
        let file = EnvFile.read(#"PASSWORT="geheim#1234""#, name: ".env")
        #expect(file.value(of: "PASSWORT") == "geheim#1234")
    }

    @Test
    func aCommentAfterAnUnquotedValueIsCutOff() {
        let file = EnvFile.read("PORT=8080 # der übliche", name: ".env")
        #expect(file.value(of: "PORT") == "8080")
    }

    @Test
    func escapesInsideDoubleQuotesAreResolved() {
        let file = EnvFile.read(#"TEXT="erste\nzweite""#, name: ".env")
        #expect(file.value(of: "TEXT") == "erste\nzweite")
    }

    /// In einfachen Anführungszeichen bedeutet nichts etwas — auch der
    /// Rückstrich nicht.
    @Test
    func singleQuotesKeepEverything() {
        let file = EnvFile.read(#"PFAD='C:\neu'"#, name: ".env")
        #expect(file.value(of: "PFAD") == #"C:\neu"#)
    }

    // MARK: - Was nicht aufgeht

    @Test
    func aLineWithoutAnEqualsSignIsReported() throws {
        let file = EnvFile.read(
            """
            PORT=8080
            das ist keine Zuweisung
            """,
            name: ".env"
        )
        #expect(file.entries.count == 1)
        let problem = try #require(file.problems.first)
        #expect(problem.kind == .unreadable)
        #expect(problem.line == 2)
    }

    /// Der häufigste Grund, warum eine Einstellung „nicht ankommt": Sie steht
    /// zweimal drin, und die zweite gewinnt.
    @Test
    func theLastOneWinsAndTheDuplicateIsReported() throws {
        let file = EnvFile.read(
            """
            PORT=8080
            PORT=9090
            """,
            name: ".env"
        )
        #expect(file.entries.count == 1)
        #expect(file.value(of: "PORT") == "9090")
        let problem = try #require(file.problems.first)
        #expect(problem.kind == .duplicate)
        #expect(problem.subject == "PORT")
    }

    @Test
    func anEmptyFileIsNoProblem() {
        let file = EnvFile.read("", name: ".env")
        #expect(file.entries.isEmpty)
        #expect(file.problems.isEmpty)
    }
}

@Suite("Umgebungsdateien vergleichen")
struct EnvComparisonTests {
    private var comparison: EnvComparison {
        EnvComparison([
            EnvFile.read(
                """
                DATABASE_URL=postgres://localhost/anvil
                PORT=8080
                NUR_LOKAL=ja
                LEER=
                """,
                name: ".env"
            ),
            EnvFile.read(
                """
                DATABASE_URL=postgres://server/anvil
                PORT=8080
                SENTRY=abc
                LEER=
                """,
                name: ".env.production"
            )
        ])
    }

    @Test
    func everyKeyFromEveryFileShowsUpOnce() {
        #expect(comparison.keys == ["DATABASE_URL", "LEER", "NUR_LOKAL", "PORT", "SENTRY"])
    }

    @Test
    func aMissingKeyIsFound() throws {
        let row = try #require(comparison.rows.first { $0.key == "SENTRY" })
        #expect(row.presence == [.missing, .set])
        #expect(row.isMissingSomewhere)
    }

    @Test
    func anEmptyValueIsNeitherSetNorMissing() throws {
        let row = try #require(comparison.rows.first { $0.key == "LEER" })
        #expect(row.presence == [.empty, .empty])
        #expect(!row.isMissingSomewhere)
        #expect(row.isEmptySomewhere)
    }

    /// Der Punkt der Übung: Der Unterschied wird gemeldet, ohne dass ein Wert
    /// irgendwo auftaucht.
    @Test
    func differingValuesAreFoundWithoutShowingThem() throws {
        let row = try #require(comparison.rows.first { $0.key == "DATABASE_URL" })
        #expect(!row.isSame)
        #expect(comparison.differing.map(\.key) == ["DATABASE_URL"])

        let report = comparison.report()
        #expect(!report.contains("postgres"))
        #expect(report.contains("DATABASE_URL"))
    }

    @Test
    func equalValuesCountAsTheSame() throws {
        let row = try #require(comparison.rows.first { $0.key == "PORT" })
        #expect(row.isSame)
        #expect(row.isEverywhere)
    }

    /// Ein Schlüssel, den nur eine Datei hat, fehlt in der anderen — das ist
    /// kein Unterschied im Wert.
    @Test
    func aKeyInOnlyOneFileIsNotADifference() throws {
        let row = try #require(comparison.rows.first { $0.key == "NUR_LOKAL" })
        #expect(row.isSame)
        #expect(row.isMissingSomewhere)
    }

    @Test
    func whatOnlyOneFileHasIsListed() {
        #expect(comparison.onlyIn(0).map(\.key) == ["NUR_LOKAL"])
        #expect(comparison.onlyIn(1).map(\.key) == ["SENTRY"])
        #expect(comparison.onlyIn(9).isEmpty)
    }

    @Test
    func theMissingLinesAreReadyToPaste() {
        #expect(comparison.missingLines(for: 0) == "SENTRY=")
        #expect(comparison.missingLines(for: 1) == "NUR_LOKAL=")
    }

    @Test
    func theFilterNarrowsTheList() {
        #expect(comparison.filtered(.all).count == 5)
        #expect(comparison.filtered(.missing).map(\.key) == ["NUR_LOKAL", "SENTRY"])
        #expect(comparison.filtered(.differing).map(\.key) == ["DATABASE_URL"])
    }

    @Test
    func theReportHasAColumnPerFile() {
        #expect(comparison.reportColumns.count == comparison.files.count + 2)
        let lines = comparison.report().components(separatedBy: "\n")
        #expect(lines.count == comparison.rows.count + 1)
        #expect(lines.allSatisfy {
            $0.components(separatedBy: "\t").count == comparison.reportColumns.count
        })
    }

    @Test
    func nothingIsNoError() {
        let empty = EnvComparison.empty
        #expect(empty.isEmpty)
        #expect(empty.keys.isEmpty)
        #expect(empty.rows.isEmpty)
        #expect(empty.missingLines(for: 0).isEmpty)
    }
}
