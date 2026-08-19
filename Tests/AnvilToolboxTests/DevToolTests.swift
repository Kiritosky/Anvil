import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("DevToolCatalog")
struct DevToolCatalogTests {
    private func run(_ tool: TextTool, _ modeID: String, _ input: String = "") throws -> String {
        try tool.run(input, modeID: modeID)
    }

    @Test
    func identifiersAreUniqueAcrossEveryCatalog() {
        let ids = (TextToolCatalog.all + EverydayToolCatalog.all + DevToolCatalog.all).map(\.id.rawValue)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - Number bases

    @Test
    func readsEveryPrefix() throws {
        #expect(try DevToolCatalog.parseInteger("255") == 255)
        #expect(try DevToolCatalog.parseInteger("0xFF") == 255)
        #expect(try DevToolCatalog.parseInteger("#ff") == 255)
        #expect(try DevToolCatalog.parseInteger("0b1111_1111") == 255)
        #expect(try DevToolCatalog.parseInteger("0o377") == 255)
        #expect(try DevToolCatalog.parseInteger("-16") == -16)
    }

    @Test
    func refusesWhatIsNotANumber() {
        #expect(throws: AnvilError.self) { try DevToolCatalog.parseInteger("zwölf") }
        #expect(throws: AnvilError.self) { try DevToolCatalog.parseInteger("0x") }
        #expect(throws: AnvilError.self) { try DevToolCatalog.parseInteger("0b12") }
    }

    @Test
    func convertsBetweenBases() throws {
        #expect(try run(DevToolCatalog.numbers, "hex", "255") == "0xFF")
        #expect(try run(DevToolCatalog.numbers, "oct", "255") == "0o377")
        #expect(try run(DevToolCatalog.numbers, "dec", "0xFF") == "255")
    }

    @Test
    func groupsBinaryDigitsFromTheRight() {
        #expect(DevToolCatalog.grouped("11111111", by: 4) == "1111_1111")
        #expect(DevToolCatalog.grouped("101", by: 4) == "101")
        #expect(DevToolCatalog.grouped("110101", by: 4) == "11_0101")
    }

    // MARK: - Unicode

    @Test
    func namesTheCharacters() throws {
        let result = try run(DevToolCatalog.unicode, "breakdown", "A")
        #expect(result.contains("U+0041"))
        #expect(result.contains("LATIN CAPITAL LETTER A"))
    }

    @Test
    func findsTheInvisibleTroublemakers() throws {
        let result = try run(DevToolCatalog.unicode, "suspicious", "Hallo\u{00A0}Welt")
        #expect(result.contains("U+00A0"))
        #expect(!result.contains("U+0048"), "gewöhnliche Buchstaben gehören nicht in diese Liste")
    }

    @Test
    func saysSoWhenNothingIsSuspicious() throws {
        let result = try run(DevToolCatalog.unicode, "suspicious", "Hallo Welt")
        #expect(result.contains("Nichts Auffälliges"))
    }

    @Test
    func writesUTF8Bytes() throws {
        #expect(try run(DevToolCatalog.unicode, "utf8", "AÄ") == "41 C3 84")
    }

    @Test
    func escapesOnlyWhatIsNotASCII() throws {
        #expect(try run(DevToolCatalog.unicode, "escape", "Straße") == "Stra\\u{00DF}e")
    }

    // MARK: - Permissions

    @Test
    func convertsPermissionsBothWays() throws {
        #expect(try run(DevToolCatalog.permissions, "convert", "755") == "rwxr-xr-x")
        #expect(try run(DevToolCatalog.permissions, "convert", "rwxr-xr-x") == "755")
        #expect(try run(DevToolCatalog.permissions, "convert", "644") == "rw-r--r--")
    }

    @Test
    func acceptsTheTypeCharacterFromLS() throws {
        #expect(try run(DevToolCatalog.permissions, "convert", "-rw-r--r--") == "644")
    }

    @Test
    func explainsWhoMayDoWhat() throws {
        let result = try run(DevToolCatalog.permissions, "explain", "640")
        #expect(result.contains("640"))
        #expect(result.contains("rw-r-----"))
        #expect(result.contains("Eigentümer"))
    }

    @Test
    func refusesNonsensePermissions() {
        #expect(throws: AnvilError.self) { try run(DevToolCatalog.permissions, "convert", "999") }
        #expect(throws: AnvilError.self) { try run(DevToolCatalog.permissions, "convert", "rwx") }
    }

    // MARK: - Status codes

    @Test
    func looksUpASingleCode() throws {
        let result = try run(DevToolCatalog.statusCodes, "lookup", "404")
        #expect(result.hasPrefix("404 Not Found"))
    }

    @Test
    func listsAWholeClass() throws {
        let result = try run(DevToolCatalog.statusCodes, "lookup", "5")
        #expect(result.contains("500"))
        #expect(result.contains("503"))
        #expect(!result.contains("404"))
    }

    @Test
    func refusesCodesItDoesNotKnow() {
        #expect(throws: AnvilError.self) { try run(DevToolCatalog.statusCodes, "lookup", "999") }
        #expect(throws: AnvilError.self) { try run(DevToolCatalog.statusCodes, "lookup", "keine ahnung") }
    }
}

@Suite("CronExpression")
struct CronExpressionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar
    }

    /// 2024-01-01 was a Monday — a fixed point to reason about.
    private var newYear2024: Date {
        calendar.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 0, minute: 0)) ?? .now
    }

    @Test
    func expandsEveryFieldSyntax() throws {
        let expression = try CronExpression(parsing: "*/15 9-17 * * 1-5")
        #expect(expression.minutes == [0, 15, 30, 45])
        #expect(expression.hours == Set(9...17))
        #expect(expression.weekdays == Set(1...5))
        #expect(expression.daysOfMonth == Set(1...31))
    }

    @Test
    func acceptsListsAndNames() throws {
        let expression = try CronExpression(parsing: "0 0 1 jan,jul mon")
        #expect(expression.months == [1, 7])
        #expect(expression.weekdays == [1])
    }

    @Test
    func treatsSevenAsSunday() throws {
        #expect(try CronExpression(parsing: "0 0 * * 7").weekdays == [0])
    }

    @Test
    func refusesBrokenExpressions() {
        #expect(throws: AnvilError.self) { try CronExpression(parsing: "* * *") }
        #expect(throws: AnvilError.self) { try CronExpression(parsing: "99 * * * *") }
        #expect(throws: AnvilError.self) { try CronExpression(parsing: "*/0 * * * *") }
        #expect(throws: AnvilError.self) { try CronExpression(parsing: "5-1 * * * *") }
    }

    @Test
    func findsTheNextTimes() throws {
        let expression = try CronExpression(parsing: "0 9 * * *")
        let next = expression.upcoming(count: 3, after: newYear2024, calendar: calendar)

        #expect(next.count == 3)
        let components = calendar.dateComponents([.hour, .minute, .day], from: next[0])
        #expect(components.hour == 9)
        #expect(components.minute == 0)
        #expect(components.day == 1)

        #expect(next[1] > next[0])
        #expect(next[2].timeIntervalSince(next[0]) == 2 * 24 * 3600)
    }

    @Test
    func skipsToTheNextWeekday() throws {
        let saturday = calendar.date(from: DateComponents(year: 2024, month: 1, day: 6, hour: 12)) ?? .now
        let expression = try CronExpression(parsing: "0 9 * * 1-5")
        let next = expression.upcoming(count: 1, after: saturday, calendar: calendar)

        let components = calendar.dateComponents([.day, .weekday], from: try #require(next.first))
        #expect(components.day == 8)
        #expect(components.weekday == 2, "Montag")
    }

    @Test
    func combinesTheTwoDayFieldsWithOr() throws {
        let expression = try CronExpression(parsing: "0 0 1 * 0")
        let dates = expression.upcoming(count: 6, after: newYear2024, calendar: calendar)
        let days = dates.map { calendar.component(.day, from: $0) }

        #expect(days.contains(7), "Sonntag der 7.")
        #expect(days.contains(1), "der Erste, obwohl er kein Sonntag ist")
    }

    @Test
    func explainsInPlainGerman() throws {
        #expect(try CronExpression(parsing: "*/15 * * * *").explanation.contains("alle 15 Minuten"))
        #expect(try CronExpression(parsing: "0 9 * * 1-5").explanation.contains("montags"))
        #expect(try CronExpression(parsing: "* * * * *").explanation.contains("jede Minute"))
    }

    @Test
    func explainsTheMonth() throws {
        let explanation = try CronExpression(parsing: "0 0 1 1 *").explanation
        #expect(explanation.contains("Januar"))
        #expect(explanation.contains("1."))
    }
}
