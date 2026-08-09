import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Dauer lesen")
struct DurationParsingTests {
    @Test(arguments: [
        ("90m", 5400.0),
        ("1h 30m", 5400.0),
        ("1h30m", 5400.0),
        ("2h", 7200.0),
        ("1,5h", 5400.0),
        ("1.5h", 5400.0),
        ("2 Tage", 172_800.0),
        ("2d 4h", 187_200.0),
        ("1w", 604_800.0),
        ("45s", 45.0),
        ("500ms", 0.5),
        ("30", 30.0),
        ("1 Stunde 30 Minuten", 5400.0),
        ("2 STD", 7200.0)
    ])
    func durationsAreReadTheWayTheyAreWritten(_ text: String, _ expected: TimeInterval) {
        #expect(TimeMath.seconds(parsing: text) == expected)
    }

    /// `1:30` ist anderthalb Stunden — wer das schreibt, meint die Uhr.
    @Test(arguments: [
        ("1:30", 5400.0),
        ("1:30:00", 5400.0),
        ("0:45", 2700.0),
        ("52:30:00", 189_000.0),
        ("-1:30", -5400.0)
    ])
    func clockNotationIsHoursFirst(_ text: String, _ expected: TimeInterval) {
        #expect(TimeMath.seconds(parsing: text) == expected)
    }

    /// Keine Dauer ist etwas anderes als die Dauer null — daran entscheidet
    /// die Oberfläche, ob sie überhaupt ein Ergebnis zeigt.
    @Test(arguments: ["", "   ", "morgen", "1x", "1:2:3:4", "1::2", "h", "1,2,3h"])
    func whatIsNotADurationIsNil(_ text: String) {
        #expect(TimeMath.seconds(parsing: text) == nil)
    }

    @Test
    func zeroIsADurationAndNotNothing() {
        #expect(TimeMath.seconds(parsing: "0") == 0)
        #expect(TimeMath.seconds(parsing: "0s") == 0)
    }
}

@Suite("Dauer schreiben")
struct DurationFormattingTests {
    @Test
    func theCompactFormLeavesOutWhatIsZero() {
        #expect(TimeMath.text(5400, style: .compact) == "1h 30m")
        #expect(TimeMath.text(187_200, style: .compact) == "2d 4h")
        #expect(TimeMath.text(45, style: .compact) == "45s")
        #expect(TimeMath.text(0, style: .compact) == "0s")
    }

    /// Die Stunden laufen weiter, statt bei 24 umzuspringen: 52:30:00 ist eine
    /// Dauer, 04:30:00 wäre eine Uhrzeit.
    @Test
    func clockNotationDoesNotWrapAtTwentyFour() {
        #expect(TimeMath.text(189_000, style: .clock) == "52:30:00")
        #expect(TimeMath.text(5400, style: .clock) == "1:30:00")
        #expect(TimeMath.text(59, style: .clock) == "0:00:59")
    }

    @Test
    func decimalHoursUseACommaLikeTheRestOfTheApp() {
        #expect(TimeMath.text(5400, style: .decimalHours) == "1,50 h")
        #expect(TimeMath.text(27_000, style: .decimalHours) == "7,50 h")
    }

    @Test
    func negativeDurationsKeepTheirSign() {
        #expect(TimeMath.text(-5400, style: .clock) == "−1:30:00")
        #expect(TimeMath.text(-5400, style: .compact).hasPrefix("−"))
    }

    @Test
    func writingAndReadingBackGivesTheSameDuration() {
        for seconds in [45.0, 5400.0, 187_200.0, 604_800.0] {
            let written = TimeMath.text(seconds, style: .compact)
            #expect(TimeMath.seconds(parsing: written) == seconds)
        }
    }
}

@Suite("Zeitstempel")
struct TimestampTests {
    /// Die Einheiten liegen drei Zehnerpotenzen auseinander, deshalb verrät
    /// die Stellenzahl, was gemeint war.
    @Test
    func theUnitIsGuessedFromTheNumberOfDigits() {
        #expect(TimeMath.timestamp(parsing: "1786310000")?.unit == .seconds)
        #expect(TimeMath.timestamp(parsing: "1786310000000")?.unit == .milliseconds)
        #expect(TimeMath.timestamp(parsing: "1786310000000000")?.unit == .microseconds)
        #expect(TimeMath.timestamp(parsing: "1786310000000000000")?.unit == .nanoseconds)
    }

    @Test
    func allFourUnitsMeanTheSameMoment() throws {
        let seconds = try #require(TimeMath.timestamp(parsing: "1786310000")?.date)
        let millis = try #require(TimeMath.timestamp(parsing: "1786310000000")?.date)
        #expect(abs(seconds.timeIntervalSince(millis)) < 0.001)
    }

    @Test
    func theEpochItselfIsAValidTimestamp() throws {
        let date = try #require(TimeMath.timestamp(parsing: "0")?.date)
        #expect(date.timeIntervalSince1970 == 0)
    }

    @Test
    func timestampsBeforeTheEpochAreNegative() throws {
        let date = try #require(TimeMath.timestamp(parsing: "-86400")?.date)
        #expect(date.timeIntervalSince1970 == -86400)
    }

    @Test(arguments: ["", "morgen", "17.8", "1786310000x", "abc"])
    func whatIsNotATimestampIsNil(_ text: String) {
        #expect(TimeMath.timestamp(parsing: text) == nil)
    }

    @Test
    func writingAndReadingBackGivesTheSameMoment() throws {
        let date = Date(timeIntervalSince1970: 1_786_310_000)
        for unit in TimeMath.TimestampUnit.allCases {
            let text = TimeMath.timestampText(of: date, unit: unit)
            let read = try #require(TimeMath.timestamp(parsing: text)?.date)
            #expect(abs(read.timeIntervalSince(date)) < 0.001)
        }
    }

    @Test
    func isoTextCarriesTheZone() {
        let date = Date(timeIntervalSince1970: 0)
        #expect(TimeMath.isoText(of: date, in: .gmt) == "1970-01-01T00:00:00Z")
    }
}

@Suite("Zeitpunkte lesen")
struct DateParsingTests {
    private let zone = TimeZone(identifier: "UTC") ?? .gmt

    @Test(arguments: [
        "2026-08-09T21:00:00Z",
        "2026-08-09 21:00:00",
        "2026-08-09"
    ])
    func theUsualWaysOfWritingADateAreRead(_ text: String) {
        #expect(TimeMath.date(parsing: text, in: zone) != nil)
    }

    @Test
    func theGermanWayIsReadToo() throws {
        let german = try #require(TimeMath.date(parsing: "09.08.2026", in: zone))
        let iso = try #require(TimeMath.date(parsing: "2026-08-09", in: zone))
        #expect(german == iso)
    }

    @Test
    func aTimestampIsAlsoADate() throws {
        let date = try #require(TimeMath.date(parsing: "0", in: zone))
        #expect(date.timeIntervalSince1970 == 0)
    }

    @Test(arguments: ["", "irgendwann", "32.13.2026"])
    func nonsenseIsNil(_ text: String) {
        #expect(TimeMath.date(parsing: text, in: zone) == nil)
    }
}

@Suite("Abstände")
struct SpanTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func day(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text) ?? Date(timeIntervalSince1970: 0)
    }

    /// Montag bis Freitag sind fünf Arbeitstage — beide Enden gezählt, so wie
    /// eine Planung zählt.
    @Test
    func aWeekFromMondayToFridayIsFiveWorkdays() {
        // 2026-08-10 ist ein Montag.
        #expect(TimeMath.workdays(from: day("2026-08-10"), to: day("2026-08-14"), calendar: calendar) == 5)
    }

    @Test
    func aWeekendCountsForNothing() {
        // 2026-08-15 Samstag, 2026-08-16 Sonntag.
        #expect(TimeMath.workdays(from: day("2026-08-15"), to: day("2026-08-16"), calendar: calendar) == 0)
    }

    @Test
    func oneDayIsOneOrNone() {
        #expect(TimeMath.workdays(from: day("2026-08-10"), to: day("2026-08-10"), calendar: calendar) == 1)
        #expect(TimeMath.workdays(from: day("2026-08-15"), to: day("2026-08-15"), calendar: calendar) == 0)
    }

    /// Über ganze Wochen wird gerechnet und nicht gezählt — hier fiele eine
    /// Schleife über 3653 Tage auf.
    @Test
    func tenYearsAreCountedWithoutWalkingEveryDay() {
        let count = TimeMath.workdays(from: day("2016-01-04"), to: day("2025-12-26"), calendar: calendar)
        // 3644 Tage insgesamt, davon 520 volle Wochen und ein Rest.
        #expect(count > 2500)
        #expect(count < 2700)
    }

    @Test
    func backwardsIsTheSameCountWithAMinus() {
        let forward = TimeMath.workdays(from: day("2026-08-10"), to: day("2026-08-14"), calendar: calendar)
        let backward = TimeMath.workdays(from: day("2026-08-14"), to: day("2026-08-10"), calendar: calendar)
        #expect(backward == -forward)
    }

    /// Jede Einheit ist der volle Abstand und nicht der Rest nach der
    /// nächstgrößeren: zwischen zwei Daten liegen 428 Tage, nicht 3.
    @Test
    func everyUnitIsTheWholeDistance() {
        let span = TimeMath.span(from: day("2025-01-01"), to: day("2026-03-05"), calendar: calendar)
        #expect(span.days == 428)
        #expect(span.months == 14)
        #expect(span.years == 1)
        #expect(span.weeks == 61)
    }

    @Test
    func aSpanBackwardsIsNegative() {
        let span = TimeMath.span(from: day("2026-03-05"), to: day("2025-01-01"), calendar: calendar)
        #expect(span.days == -428)
        #expect(span.seconds < 0)
    }
}

@Suite("Kalenderwoche")
struct ISOWeekTests {
    private let zone = TimeZone(identifier: "UTC") ?? .gmt

    private func day(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text) ?? Date(timeIntervalSince1970: 0)
    }

    /// Der Fall, an dem sich die Zählweisen unterscheiden: der 1. Januar
    /// gehört nach ISO 8601 oft noch zur letzten Woche des Vorjahres.
    @Test
    func theFirstOfJanuaryCanBelongToTheYearBefore() {
        let week = TimeMath.isoWeek(of: day("2027-01-01"), in: zone)
        #expect(week.week == 53)
        #expect(week.year == 2026)
    }

    @Test
    func theFourthOfJanuaryIsAlwaysInWeekOne() {
        for year in 2024...2030 {
            let week = TimeMath.isoWeek(of: day("\(year)-01-04"), in: zone)
            #expect(week.week == 1)
            #expect(week.year == year)
        }
    }
}
