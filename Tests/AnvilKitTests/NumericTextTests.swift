import Foundation
import Testing

@testable import AnvilKit

@Suite("Zahlen aus Text lesen")
struct NumericTextTests {
    // MARK: - Die ganze Zelle

    @Test(arguments: [
        ("42", 42.0),
        ("-3,5", -3.5),
        ("1.234,50", 1234.5),
        ("1,234.50", 1234.5),
        ("1 234", 1234.0),
        ("1\u{00A0}234", 1234.0)
    ])
    func aWholeCellIsRead(text: String, expected: Double) {
        #expect(NumericText.value(in: text) == expected)
    }

    /// Für Summen und Mittelwerte zählt nur, was ganz eine Zahl ist — sonst
    /// stünde unter einer Spalte mit „12 MB" eine Summe von 12.
    @Test(arguments: ["", "12 MB", "Zeile 3", "1.2.3", "—"])
    func halfANumberIsNoNumber(text: String) {
        #expect(NumericText.value(in: text) == nil)
    }

    // MARK: - Die Zahl am Anfang

    @Test
    func theNumberAtTheFrontCounts() {
        #expect(NumericText.leadingValue(in: "12 Zeilen") == 12)
        #expect(NumericText.leadingValue(in: "87 %") == 87)
        #expect(NumericText.leadingValue(in: "-4 Grad") == -4)
    }

    @Test
    func aSizeIsWorthItsUnit() {
        #expect(NumericText.leadingValue(in: "2 MB") == 2_000_000)
        #expect(NumericText.leadingValue(in: "900 kB") == 900_000)
        #expect(NumericText.leadingValue(in: "1 GiB") == 1_073_741_824)
        #expect(NumericText.leadingValue(in: "512 Bytes") == 512)
    }

    /// Ohne diese Umrechnung stünde „900 kB" hinter „1,2 MB".
    @Test
    func aBigUnitBeatsABigNumber() throws {
        let small = try #require(NumericText.leadingValue(in: "900 kB"))
        let large = try #require(NumericText.leadingValue(in: "1,2 MB"))
        #expect(small < large)
    }

    @Test(arguments: ["", "MB", "kein Anfang", "—"])
    func textWithoutANumberStaysText(text: String) {
        #expect(NumericText.leadingValue(in: text) == nil)
    }

    /// Eine Versionsnummer ist keine Zahl — sonst wäre 1.2.3 kleiner als 1.10.
    @Test
    func aVersionIsNoNumber() {
        #expect(NumericText.leadingValue(in: "1.2.3") == nil)
    }
}
