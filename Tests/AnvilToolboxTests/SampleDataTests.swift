import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Testdaten")
struct SampleDataTests {
    /// Der ganze Grund für den Startwert: Zufällige Testdaten sind für einen
    /// Screenshot gut und für alles andere unbrauchbar.
    @Test
    func theSameSeedGivesTheSameTable() {
        let first = SampleData(count: 20, fields: SampleData.Field.allCases, seed: 42)
        let second = SampleData(count: 20, fields: SampleData.Field.allCases, seed: 42)
        #expect(first.rows == second.rows)
    }

    @Test
    func aDifferentSeedGivesADifferentTable() {
        let first = SampleData(count: 20, fields: [.fullName], seed: 1)
        let second = SampleData(count: 20, fields: [.fullName], seed: 2)
        #expect(first.rows != second.rows)
    }

    /// Auch ein Startwert von 0 muss eine Folge ergeben und nicht zwanzigmal
    /// dieselbe Zeile.
    @Test
    func aSeedOfZeroStillVaries() {
        let data = SampleData(count: 20, fields: [.fullName], seed: 0)
        #expect(Set(data.rows.map { $0[0] }).count > 1)
    }

    @Test
    func theColumnsAreTheOnesThatWereAskedFor() {
        let data = SampleData(count: 3, fields: [.id, .email, .city])
        #expect(data.rows.allSatisfy { $0.count == 3 })
        #expect(data.rows[0][0] == "1")
        #expect(data.rows[2][0] == "3")
    }

    /// Ohne Spalten gäbe es eine Tabelle ohne alles.
    @Test
    func noFieldsFallsBackToTheUsualOnes() {
        let data = SampleData(count: 1, fields: [])
        #expect(data.fields == SampleData.Field.common)
    }

    @Test
    func askingForNothingGivesNothing() {
        #expect(SampleData(count: 0, fields: [.id]).rows.isEmpty)
        #expect(SampleData(count: -5, fields: [.id]).rows.isEmpty)
    }

    /// Testdaten, bei denen „Anna Müller" die Adresse `heinz.schulz@…` hat,
    /// fallen beim ersten Blick auf.
    @Test
    func theEmailBelongsToTheName() {
        let data = SampleData(count: 30, fields: [.firstName, .lastName, .email])
        for row in data.rows {
            let first = row[0].lowercased()
                .replacingOccurrences(of: "ä", with: "ae")
                .replacingOccurrences(of: "ö", with: "oe")
                .replacingOccurrences(of: "ü", with: "ue")
            #expect(row[2].hasPrefix(first))
        }
    }

    @Test
    func anEmailHasNoUmlautsAndNoSharpS() {
        let address = SampleData.email(firstName: "Jürgen", lastName: "Weiß", company: "Kontur")
        #expect(address == "juergen.weiss@kontur.example")
    }

    @Test
    func theRegionDecidesWhereTheNamesComeFrom() {
        let german = SampleData(count: 40, fields: [.lastName], region: .german, seed: 7)
        let english = SampleData(count: 40, fields: [.lastName], region: .english, seed: 7)
        #expect(german.rows.contains { SampleData.germanLastNames.contains($0[0]) })
        #expect(english.rows.allSatisfy { SampleData.englishLastNames.contains($0[0]) })
    }
}

@Suite("IBAN")
struct SampleIBANTests {
    /// Eine erfundene Prüfziffer wäre wertlos: Testdaten braucht man gerade
    /// dort, wo eine Prüfung läuft.
    @Test
    func theCheckDigitsMatchTheKnownExample() {
        #expect(
            SampleData.germanIBAN(bank: 37_040_044, account: 532_013_000)
                == "DE89370400440532013000"
        )
    }

    /// Eine zehnstellige Kontonummer passt in keinen 32-Bit-Wert. Mit `%d`
    /// statt `%ld` kam sie abgeschnitten und mitunter negativ heraus — und
    /// die IBAN war 23 Zeichen lang.
    @Test
    func aTenDigitAccountNumberIsNotTruncated() {
        let iban = SampleData.germanIBAN(bank: 99_999_999, account: 9_999_999_999)
        #expect(iban == "DE85999999999999999999")
        #expect(iban.count == 22)
        #expect(!iban.contains("-"))
    }

    @Test
    func everyGeneratedIBANPassesTheMod97Check() {
        let data = SampleData(count: 50, fields: [.iban], seed: 3)
        for row in data.rows {
            let iban = row[0]
            #expect(iban.count == 22)
            #expect(iban.hasPrefix("DE"))
            // Umgestellt und in Zahlen übersetzt muss der Rest 1 sein.
            let rearranged = String(iban.dropFirst(4)) + "1314" + String(iban.dropFirst(2).prefix(2))
            #expect(SampleData.mod97(rearranged) == 1)
        }
    }

    @Test
    func mod97WorksOnNumbersTooLongForAnInteger() {
        // 34 Stellen — kein UInt64 fasst das.
        #expect(SampleData.mod97("1234567890123456789012345678901234") == 53)
        #expect(SampleData.mod97("97") == 0)
        #expect(SampleData.mod97("98") == 1)
    }
}

@Suite("Erzeugte UUIDs")
struct SampleUUIDTests {
    @Test
    func theyLookLikeUUIDsAndCarryTheirVersion() {
        let data = SampleData(count: 20, fields: [.uuid], seed: 5)
        for row in data.rows {
            let value = row[0]
            #expect(value.count == 36)
            #expect(value.split(separator: "-").map(\.count) == [8, 4, 4, 4, 12])
            // Fassung 4, Variante 1 — sonst ist es keine UUID, sondern nur
            // hübsch.
            #expect(Array(value)[14] == "4")
            #expect("89ab".contains(Array(value)[19]))
            #expect(UUID(uuidString: value) != nil)
        }
    }

    @Test
    func theyAreAllDifferent() {
        let data = SampleData(count: 100, fields: [.uuid], seed: 9)
        #expect(Set(data.rows.map { $0[0] }).count == 100)
    }
}

@Suite("Testdaten ausgeben")
struct SampleOutputTests {
    private let data = SampleData(count: 5, fields: [.id, .fullName, .amount], seed: 11)

    @Test
    func theTableHasTheChosenColumnsAsItsHeader() {
        let table = data.table
        #expect(table.header == [
            SampleData.Field.id.title,
            SampleData.Field.fullName.title,
            SampleData.Field.amount.title
        ])
        #expect(table.rowCount == 5)
    }

    /// Der Nutzen, die Ausgabe über die Tabelle laufen zu lassen: alles, was
    /// die Tabellen können, gilt hier auch.
    @Test
    func everythingTheTableCanDoWorksHereToo() throws {
        let json = data.table.json
        let parsed = try JSONSerialization.jsonObject(
            with: try #require(json.data(using: .utf8))
        ) as? [[String: Any]]
        #expect(parsed?.count == 5)

        #expect(data.table.markdown.hasPrefix("| "))
        #expect(data.table.sql(table: "kunden").contains("INSERT INTO kunden"))
    }
}
