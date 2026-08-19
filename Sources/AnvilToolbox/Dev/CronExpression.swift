import AnvilKit
import Foundation

/// A crontab line, parsed into the five sets it really is.
public struct CronExpression: Sendable {
    public let minutes: Set<Int>
    public let hours: Set<Int>
    public let daysOfMonth: Set<Int>
    public let months: Set<Int>
    public let weekdays: Set<Int>

    /// Whether the day fields were restricted — cron combines them with OR, but
    /// only when both are set, which is the part everyone gets wrong.
    private let restrictsDayOfMonth: Bool
    private let restrictsWeekday: Bool

    public init(parsing text: String) throws {
        let fields = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard fields.count == 5 else {
            throw AnvilError.invalidInput(
                localized("Ein Cron-Ausdruck hat fünf Felder: Minute, Stunde, Tag, Monat, Wochentag.")
            )
        }

        minutes = try Self.expand(fields[0], range: 0...59, names: [:], label: localized("Minute"))
        hours = try Self.expand(fields[1], range: 0...23, names: [:], label: localized("Stunde"))
        daysOfMonth = try Self.expand(fields[2], range: 1...31, names: [:], label: localized("Tag"))
        months = try Self.expand(fields[3], range: 1...12, names: Self.monthNames, label: localized("Monat"))
        let parsedWeekdays = try Self.expand(fields[4], range: 0...7, names: Self.weekdayNames, label: localized("Wochentag"))
        weekdays = Set(parsedWeekdays.map { $0 == 7 ? 0 : $0 })

        restrictsDayOfMonth = fields[2] != "*"
        restrictsWeekday = fields[4] != "*"
    }

    // MARK: - Parsing

    /// Expands one field: `*`, `5`, `1-5`, `*/15`, `1-5/2`, `mon,wed` and any
    /// comma-separated mix of those.
    static func expand(
        _ field: String,
        range: ClosedRange<Int>,
        names: [String: Int],
        label: String
    ) throws -> Set<Int> {
        var result: Set<Int> = []

        for part in field.lowercased().split(separator: ",") {
            let pieces = part.split(separator: "/")
            guard pieces.count <= 2 else {
                throw AnvilError.invalidInput(localized("„\(String(part))\" ergibt im Feld \(label) keinen Sinn."))
            }

            let step = pieces.count == 2 ? Int(pieces[1]) : 1
            guard let step, step > 0 else {
                throw AnvilError.invalidInput(localized("Die Schrittweite in \(label) muss eine Zahl über null sein."))
            }

            let base = pieces[0]
            let bounds: ClosedRange<Int>

            if base == "*" {
                bounds = range
            } else if base.contains("-") {
                let ends = base.split(separator: "-")
                guard ends.count == 2,
                      let lower = Self.value(String(ends[0]), names: names),
                      let upper = Self.value(String(ends[1]), names: names),
                      lower <= upper,
                      range.contains(lower), range.contains(upper)
                else {
                    throw AnvilError.invalidInput(localized("„\(String(base))\" ist kein gültiger Bereich für \(label)."))
                }
                bounds = lower...upper
            } else {
                guard let single = Self.value(String(base), names: names), range.contains(single) else {
                    throw AnvilError.invalidInput(localized("„\(String(base))\" liegt außerhalb von \(label)."))
                }
                bounds = single...single
            }

            for value in stride(from: bounds.lowerBound, through: bounds.upperBound, by: step) {
                result.insert(value)
            }
        }

        guard !result.isEmpty else {
            throw AnvilError.invalidInput(localized("Das Feld \(label) ist leer."))
        }
        return result
    }

    private static func value(_ text: String, names: [String: Int]) -> Int? {
        names[text] ?? Int(text)
    }

    static let monthNames = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
        "mär": 3, "mai": 5, "okt": 10, "dez": 12
    ]

    static let weekdayNames = [
        "sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6,
        "son": 0, "die": 2, "mit": 3, "don": 4, "fre": 5, "sam": 6
    ]

    // MARK: - Matching

    /// Whether the expression fires at that minute.
    public func matches(_ components: DateComponents) -> Bool {
        guard let minute = components.minute,
              let hour = components.hour,
              let day = components.day,
              let month = components.month,
              let weekday = components.weekday
        else { return false }

        guard minutes.contains(minute), hours.contains(hour), months.contains(month) else {
            return false
        }

        let cronWeekday = weekday - 1
        let dayMatches = daysOfMonth.contains(day)
        let weekdayMatches = weekdays.contains(cronWeekday)

        if restrictsDayOfMonth, restrictsWeekday { return dayMatches || weekdayMatches }
        if restrictsDayOfMonth { return dayMatches }
        if restrictsWeekday { return weekdayMatches }
        return true
    }

    /// The next `count` times this fires, starting after `date`.
    public func upcoming(count: Int, after date: Date = .now, calendar: Calendar = .current) -> [Date] {
        var found: [Date] = []
        let startOfToday = calendar.startOfDay(for: date)
        let sortedHours = hours.sorted()
        let sortedMinutes = minutes.sorted()

        for dayOffset in 0..<(366 * 4) {
            guard found.count < count else { break }
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }

            let dayComponents = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
            for hour in sortedHours {
                for minute in sortedMinutes {
                    var candidate = dayComponents
                    candidate.hour = hour
                    candidate.minute = minute
                    guard matches(candidate) else { continue }

                    var wanted = DateComponents()
                    wanted.year = dayComponents.year
                    wanted.month = dayComponents.month
                    wanted.day = dayComponents.day
                    wanted.hour = hour
                    wanted.minute = minute

                    guard let fireDate = calendar.date(from: wanted), fireDate > date else { continue }

                    found.append(fireDate)
                    if found.count == count { return found }
                }
            }
        }

        return found
    }

    // MARK: - Explaining

    /// The expression in one German sentence.
    public var explanation: String {
        let minutePart = describe(minutes, range: 0...59, unit: .minute)
        let hourPart = describe(hours, range: 0...23, unit: .hour)

        var sentence = localized("Läuft \(minutePart) \(hourPart)")

        if restrictsDayOfMonth {
            sentence += localized(", am \(list(daysOfMonth)). des Monats")
        }
        if months.count < 12 {
            let names = months.sorted().map { Self.monthTitles[$0 - 1] }.joined(separator: ", ")
            sentence += localized(", im \(names)")
        }
        if restrictsWeekday {
            let names = weekdays.sorted().map { Self.weekdayTitles[$0] }.joined(separator: ", ")
            sentence += localized(", \(names)")
        }

        return sentence + "."
    }

    private enum Unit { case minute, hour }

    private func describe(_ values: Set<Int>, range: ClosedRange<Int>, unit: Unit) -> String {
        if values.count == range.count {
            return unit == .minute ? localized("jede Minute") : localized("jede Stunde")
        }

        if let step = evenStep(in: values, range: range) {
            return unit == .minute
                ? localized("alle \(step) Minuten")
                : localized("alle \(step) Stunden")
        }

        let joined = list(values)
        return unit == .minute
            ? localized("zur Minute \(joined)")
            : localized("um \(joined) Uhr")
    }

    /// Recognises `*/15` after the fact, so the sentence says "alle 15 Minuten"
    /// instead of listing four numbers.
    private func evenStep(in values: Set<Int>, range: ClosedRange<Int>) -> Int? {
        guard values.count > 2, values.contains(range.lowerBound) else { return nil }
        let sorted = values.sorted()
        let step = sorted[1] - sorted[0]
        guard step > 1 else { return nil }

        let expected = Set(stride(from: range.lowerBound, through: range.upperBound, by: step))
        return expected == values ? step : nil
    }

    private func list(_ values: Set<Int>) -> String {
        values.sorted().map(String.init).joined(separator: ", ")
    }

    static let monthTitles = [
        localized("Januar"), localized("Februar"), localized("März"), localized("April"),
        localized("Mai"), localized("Juni"), localized("Juli"), localized("August"),
        localized("September"), localized("Oktober"), localized("November"), localized("Dezember")
    ]

    static let weekdayTitles = [
        localized("sonntags"), localized("montags"), localized("dienstags"),
        localized("mittwochs"), localized("donnerstags"), localized("freitags"),
        localized("samstags")
    ]
}
