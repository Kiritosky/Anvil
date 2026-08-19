import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("EverydayToolCatalog")
struct EverydayToolCatalogTests {
    private func run(_ tool: TextTool, _ modeID: String, _ input: String = "") throws -> String {
        try tool.run(input, modeID: modeID)
    }

    @Test
    func everyToolHasAtLeastOneMode() {
        for tool in EverydayToolCatalog.all {
            #expect(!tool.modes.isEmpty, "\(tool.title) hat keine Variante")
        }
    }

    @Test
    func toolIdentifiersAreUniqueAcrossBothCatalogs() {
        let ids = (TextToolCatalog.all + EverydayToolCatalog.all).map(\.id.rawValue)
        #expect(Set(ids).count == ids.count)
    }

    @Test
    func everyToolIsFiledUnderEveryday() {
        for tool in EverydayToolCatalog.all {
            #expect(tool.category == .everyday, "\(tool.title) liegt in der falschen Kategorie")
        }
    }

    // MARK: - Passwords

    @Test
    func passwordsHaveTheRequestedLength() throws {
        #expect(try run(EverydayToolCatalog.passwords, "strong16").count == 16)
        #expect(try run(EverydayToolCatalog.passwords, "strong24").count == 24)
    }

    @Test
    func passwordsAvoidCharactersThatLookAlike() {
        let password = EverydayToolCatalog.makePassword(length: 400, includesSymbols: true)
        for character in "0O1lI" {
            #expect(!password.contains(character), "\(character) ist zu leicht zu verwechseln")
        }
    }

    @Test
    func passwordsAreNotRepeated() throws {
        let batch = try run(EverydayToolCatalog.passwords, "batch")
            .components(separatedBy: .newlines)
        #expect(batch.count == 10)
        #expect(Set(batch).count == 10)
    }

    @Test
    func passphrasesUseWordsAndEndInDigits() {
        let phrase = EverydayToolCatalog.makePassphrase(words: 6)
        #expect(phrase.components(separatedBy: "-").count == 6)
        #expect(phrase.last?.isNumber == true)
    }

    @Test
    func pinsAreSixDigits() throws {
        let pin = try run(EverydayToolCatalog.passwords, "pin")
        let onlyDigits = pin.allSatisfy(\.isNumber)
        #expect(pin.count == 6)
        #expect(onlyDigits)
    }

    // MARK: - Units

    @Test
    func convertsLength() throws {
        #expect(try run(EverydayToolCatalog.units, "convert", "5 km in mi") == "3.10686 mi")
        #expect(try run(EverydayToolCatalog.units, "convert", "1 m in cm") == "100 cm")
    }

    @Test
    func convertsTemperature() throws {
        #expect(try run(EverydayToolCatalog.units, "convert", "100 °C in °F") == "212 °F")
        #expect(try run(EverydayToolCatalog.units, "convert", "0 c in k") == "273.15 K")
    }

    @Test
    func acceptsTheWaysPeopleActuallyType() throws {
        let expected = try run(EverydayToolCatalog.units, "convert", "5 km in mi")
        #expect(try run(EverydayToolCatalog.units, "convert", "5km->mi") == expected)
        #expect(try run(EverydayToolCatalog.units, "convert", "5 km nach meilen") == expected)
        #expect(try run(EverydayToolCatalog.units, "convert", "5,0 km to mi") == expected)
    }

    @Test
    func convertsDataSizesIncludingTheBinaryOnes() throws {
        #expect(try run(EverydayToolCatalog.units, "convert", "1 GiB in MiB") == "1024 MiB")
        #expect(try run(EverydayToolCatalog.units, "convert", "1 GB in MB") == "1000 MB")
    }

    @Test
    func listsEveryUnitOfTheSameFamily() throws {
        let result = try run(EverydayToolCatalog.units, "all", "1 kg")
        #expect(result.contains(" g"))
        #expect(result.contains(" lb"))
        #expect(!result.contains(" km"), "Länge gehört nicht zu Gewicht")
    }

    @Test
    func refusesUnitsThatDoNotBelongTogether() {
        #expect(throws: AnvilError.self) {
            try run(EverydayToolCatalog.units, "convert", "5 km in kg")
        }
    }

    @Test
    func refusesInputWithoutANumber() {
        #expect(throws: AnvilError.self) {
            try run(EverydayToolCatalog.units, "convert", "kilometer in meilen")
        }
    }

    @Test
    func refusesUnknownUnits() {
        #expect(throws: AnvilError.self) {
            try run(EverydayToolCatalog.units, "convert", "5 schnurrbart in mi")
        }
    }

    // MARK: - Percent

    @Test
    func calculatesAShareOfAValue() throws {
        #expect(try run(EverydayToolCatalog.percent, "solve", "19% von 250") == "47.5")
    }

    @Test
    func addsAndRemovesASurcharge() throws {
        #expect(try run(EverydayToolCatalog.percent, "solve", "250 + 19%") == "297.5")
        #expect(try run(EverydayToolCatalog.percent, "solve", "250 - 10%") == "225")
    }

    @Test
    func calculatesTheChangeBetweenTwoValues() throws {
        #expect(try run(EverydayToolCatalog.percent, "solve", "von 250 auf 300") == "+20%")
        #expect(try run(EverydayToolCatalog.percent, "solve", "von 300 auf 250") == "-16.6667%")
    }

    @Test
    func calculatesWhichShareThatIs() throws {
        #expect(try run(EverydayToolCatalog.percent, "solve", "47.5 von 250") == "19%")
    }

    @Test
    func refusesASingleNumber() {
        #expect(throws: AnvilError.self) {
            try run(EverydayToolCatalog.percent, "solve", "250")
        }
    }

    // MARK: - Time zones

    @Test
    func readsATimeOfDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt

        let date = try EverydayToolCatalog.referenceDate(
            from: "14:30",
            now: Date(timeIntervalSince1970: 1_700_000_000),
            calendar: calendar
        )
        let components = calendar.dateComponents([.hour, .minute], from: date)
        #expect(components.hour == 14)
        #expect(components.minute == 30)
    }

    @Test
    func emptyInputMeansNow() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(try EverydayToolCatalog.referenceDate(from: "   ", now: now) == now)
    }

    @Test
    func refusesImpossibleTimes() {
        #expect(throws: AnvilError.self) {
            try EverydayToolCatalog.referenceDate(from: "25:00")
        }
        #expect(throws: AnvilError.self) {
            try EverydayToolCatalog.referenceDate(from: "12:75")
        }
    }

    @Test
    func showsOneLinePerZone() {
        let clock = EverydayToolCatalog.worldClock(for: Date(timeIntervalSince1970: 1_700_000_000))
        let lines = clock.components(separatedBy: .newlines)

        #expect(lines.count == EverydayToolCatalog.worldZones.count)
        #expect(clock.contains("UTC"))
        #expect(lines.first { $0.hasPrefix("UTC") }?.contains("22:13") == true)
        #expect(lines.first { $0.hasPrefix("Tokio") }?.contains("15.11.") == true)
    }

    // MARK: - Lorem

    @Test
    func producesTheRequestedNumberOfParagraphs() throws {
        let three = try run(EverydayToolCatalog.lorem, "three")
        #expect(three.components(separatedBy: "\n\n").count == 3)
    }

    @Test
    func sentencesAreCapitalisedAndClosed() {
        let sentence = EverydayToolCatalog.loremSentences(1)
        #expect(sentence.first?.isUppercase == true)
        #expect(sentence.hasSuffix("."))
    }

    // MARK: - Formatting

    @Test
    func formatsNumbersWithoutTrailingNoise() {
        #expect(EverydayToolCatalog.formatNumber(100) == "100")
        #expect(EverydayToolCatalog.formatNumber(3.1068559611866697) == "3.10686")
        #expect(EverydayToolCatalog.formatNumber(0.5) == "0.5")
        #expect(EverydayToolCatalog.formatNumber(-16.666666) == "-16.6667")
    }
}
