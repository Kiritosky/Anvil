import AnvilKit
import Foundation

/// Rechnen mit Zeit — Dauern, Zeitstempel, Abstände.
///
/// Alles hier ist eine reine Funktion über Werte. Kein `Date()` im Inneren:
/// eine Rechnung, die weiß, wie spät es gerade ist, lässt sich nicht prüfen.
/// Die Gegenwart kommt von außen herein.
public enum TimeMath {
    // MARK: - Dauer lesen

    /// Wie lange, in Sekunden.
    ///
    /// Nimmt an, was Menschen aufschreiben: `90m`, `1h 30m`, `2 Tage`,
    /// `1,5 h`, `1:30` und `1:30:00`. Eine nackte Zahl sind Sekunden — auch am
    /// Ende, `1h30` ist also eine Stunde und dreißig **Sekunden**. Wer Minuten
    /// meint, schreibt sie hin; geraten wird hier nichts.
    ///
    /// Gibt `nil` zurück, wenn nichts davon passt — nicht `0`. Der Unterschied
    /// zwischen „keine Dauer" und „Dauer null" ist genau der, an dem eine
    /// Oberfläche entscheidet, ob sie ein Ergebnis zeigt.
    public static func seconds(parsing text: String) -> TimeInterval? {
        let work = text
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        guard !work.isEmpty else { return nil }

        if work.contains(":") { return clockSeconds(work) }

        var total: TimeInterval = 0
        var number = ""
        var unit = ""
        var sawPair = false

        func commit() -> Bool {
            guard !number.isEmpty else { return unit.isEmpty }
            guard let value = Double(number.replacingOccurrences(of: ",", with: ".")) else {
                return false
            }
            guard let factor = factor(for: unit) else { return false }
            total += value * factor
            sawPair = true
            number = ""
            unit = ""
            return true
        }

        for character in work {
            if character.isNumber || character == "." || character == "," {
                // Eine neue Zahl beginnt: das Paar davor ist fertig.
                if !unit.isEmpty, !commit() { return nil }
                number.append(character)
            } else if character.isLetter {
                unit.append(character)
            } else if character.isWhitespace {
                continue
            } else {
                return nil
            }
        }
        guard commit(), sawPair else { return nil }
        return total
    }

    /// Wie viele Sekunden eine Einheit ist. Leer heißt Sekunden.
    ///
    /// Deutsche und englische Kürzel nebeneinander, weil beides in denselben
    /// Notizen steht.
    static func factor(for unit: String) -> TimeInterval? {
        switch unit {
        case "": 1
        case "ms": 0.001
        case "s", "sek", "sekunde", "sekunden", "sec": 1
        case "m", "min", "minute", "minuten": 60
        case "h", "std", "stunde", "stunden", "hr": 3600
        case "d", "t", "tag", "tage", "tagen", "day", "days": 86400
        case "w", "woche", "wochen", "week", "weeks": 604_800
        default: nil
        }
    }

    /// `1:30` sind anderthalb Stunden, `1:30:00` auch.
    ///
    /// Zwei Felder werden als Stunden und Minuten gelesen, nicht als Minuten
    /// und Sekunden: wer `1:30` schreibt, meint fast immer die Uhr.
    static func clockSeconds(_ text: String) -> TimeInterval? {
        let isNegative = text.hasPrefix("-")
        let parts = (isNegative ? String(text.dropFirst()) : text).components(separatedBy: ":")
        guard (2...3).contains(parts.count) else { return nil }

        var values: [Double] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let value = Double(trimmed), value >= 0 else { return nil }
            values.append(value)
        }

        let total = parts.count == 2
            ? values[0] * 3600 + values[1] * 60
            : values[0] * 3600 + values[1] * 60 + values[2]
        return isNegative ? -total : total
    }

    // MARK: - Dauer schreiben

    public enum DurationStyle: String, Hashable, Sendable, CaseIterable, Identifiable {
        /// `2d 4h 30m`
        case compact
        /// `52:30:00` — die Stunden laufen weiter, statt bei 24 umzuspringen.
        case clock
        /// `4,5 h`
        case decimalHours
        /// `2 Tage, 4 Stunden, 30 Minuten`
        case words

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .compact: localized("Kurz")
            case .clock: localized("Uhrzeit-Schreibweise")
            case .decimalHours: localized("Dezimalstunden")
            case .words: localized("Ausgeschrieben")
            }
        }
    }

    public static func text(_ seconds: TimeInterval, style: DurationStyle) -> String {
        let sign = seconds < 0 ? "−" : ""
        let total = abs(seconds)

        switch style {
        case .clock:
            let whole = Int(total.rounded())
            let hours = whole / 3600
            let minutes = (whole % 3600) / 60
            let rest = whole % 60
            return sign + String(format: "%ld:%02ld:%02ld", hours, minutes, rest)

        case .decimalHours:
            let hours = total / 3600
            // Zwei Nachkommastellen: 7,5 h ist eine Angabe, 7,4999 h ist keine.
            return sign + String(format: "%.2f", hours)
                .replacingOccurrences(of: ".", with: ",") + " h"

        case .compact, .words:
            let parts = components(of: total)
            let pieces: [String]
            if style == .compact {
                pieces = [
                    parts.days > 0 ? "\(parts.days)d" : nil,
                    parts.hours > 0 ? "\(parts.hours)h" : nil,
                    parts.minutes > 0 ? "\(parts.minutes)m" : nil,
                    parts.seconds > 0 || parts.isZero ? "\(parts.seconds)s" : nil
                ].compactMap { $0 }
            } else {
                pieces = [
                    parts.days > 0 ? plural(parts.days, localized("Tag"), localized("Tage")) : nil,
                    parts.hours > 0 ? plural(parts.hours, localized("Stunde"), localized("Stunden")) : nil,
                    parts.minutes > 0 ? plural(parts.minutes, localized("Minute"), localized("Minuten")) : nil,
                    parts.seconds > 0 || parts.isZero
                        ? plural(parts.seconds, localized("Sekunde"), localized("Sekunden"))
                        : nil
                ].compactMap { $0 }
            }
            return sign + pieces.joined(separator: style == .compact ? " " : ", ")
        }
    }

    /// Eine Dauer, aufgeteilt in Tage, Stunden, Minuten, Sekunden.
    public struct Components: Sendable, Hashable {
        public let days: Int
        public let hours: Int
        public let minutes: Int
        public let seconds: Int

        public var isZero: Bool {
            days == 0 && hours == 0 && minutes == 0 && seconds == 0
        }
    }

    public static func components(of seconds: TimeInterval) -> Components {
        let whole = Int(abs(seconds).rounded())
        return Components(
            days: whole / 86400,
            hours: (whole % 86400) / 3600,
            minutes: (whole % 3600) / 60,
            seconds: whole % 60
        )
    }

    static func plural(_ count: Int, _ one: String, _ many: String) -> String {
        "\(count) \(count == 1 ? one : many)"
    }

    // MARK: - Zeitstempel

    /// In welcher Einheit ein Zeitstempel gemeint war.
    public enum TimestampUnit: String, Hashable, Sendable, CaseIterable, Identifiable {
        case seconds
        case milliseconds
        case microseconds
        case nanoseconds

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .seconds: localized("Sekunden")
            case .milliseconds: localized("Millisekunden")
            case .microseconds: localized("Mikrosekunden")
            case .nanoseconds: localized("Nanosekunden")
            }
        }

        var divisor: Double {
            switch self {
            case .seconds: 1
            case .milliseconds: 1_000
            case .microseconds: 1_000_000
            case .nanoseconds: 1_000_000_000
            }
        }
    }

    /// Liest einen Unix-Zeitstempel und rät seine Einheit an der Stellenzahl.
    ///
    /// Das geht, weil die Einheiten drei Zehnerpotenzen auseinanderliegen: seit
    /// 2001 hat ein Zeitstempel in Sekunden zehn Stellen, in Millisekunden
    /// dreizehn. Eine Zahl mit dreizehn Stellen als Sekunden zu lesen ergäbe
    /// das Jahr 440 000 — und niemand meint das.
    public static func timestamp(parsing text: String) -> (date: Date, unit: TimestampUnit)? {
        let work = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
        let isNegative = work.hasPrefix("-")
        let digits = isNegative ? String(work.dropFirst()) : work
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Double(digits)
        else { return nil }

        let unit: TimestampUnit
        switch digits.count {
        case ...11: unit = .seconds
        case 12...14: unit = .milliseconds
        case 15...17: unit = .microseconds
        default: unit = .nanoseconds
        }

        let signed = isNegative ? -value : value
        return (Date(timeIntervalSince1970: signed / unit.divisor), unit)
    }

    /// Ein Zeitpunkt als Zeitstempel, in der gewünschten Einheit.
    public static func timestampText(of date: Date, unit: TimestampUnit) -> String {
        let value = date.timeIntervalSince1970 * unit.divisor
        return String(Int64(value.rounded()))
    }

    /// ISO 8601 mit Zeitzone — das Format, in dem Zeitpunkte durch Netze
    /// gehen.
    public static func isoText(of date: Date, in zone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = zone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Liest einen Zeitpunkt: erst ISO 8601, dann die üblichen Schreibweisen.
    public static func date(parsing text: String, in zone: TimeZone) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if let (date, _) = timestamp(parsing: trimmed) { return date }

        let iso = ISO8601DateFormatter()
        iso.timeZone = zone
        for options in [
            ISO8601DateFormatter.Options([.withInternetDateTime, .withFractionalSeconds]),
            ISO8601DateFormatter.Options([.withInternetDateTime]),
            ISO8601DateFormatter.Options([.withFullDate, .withTime, .withColonSeparatorInTime]),
            ISO8601DateFormatter.Options([.withFullDate])
        ] {
            iso.formatOptions = options
            if let date = iso.date(from: trimmed) { return date }
        }

        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in [
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
            "dd.MM.yyyy HH:mm:ss", "dd.MM.yyyy HH:mm", "dd.MM.yyyy",
            "MM/dd/yyyy HH:mm", "MM/dd/yyyy"
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    // MARK: - Abstände

    /// Was zwischen zwei Zeitpunkten liegt.
    public struct Span: Sendable, Hashable {
        /// Sekunden, mit Vorzeichen: negativ, wenn das Ende vor dem Anfang
        /// liegt.
        public let seconds: TimeInterval
        /// Ganze Kalendertage dazwischen.
        public let days: Int
        /// Arbeitstage, **beide Enden mitgezählt** — so, wie eine Planung sie
        /// zählt: Montag bis Freitag sind fünf.
        public let workdays: Int
        public let weeks: Int
        public let months: Int
        public let years: Int
    }

    public static func span(
        from start: Date,
        to end: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Span {
        // Jede Einheit einzeln erfragen. Zusammen erfragt zerlegt `Calendar`
        // den Abstand („1 Jahr, 2 Monate, 3 Tage"), und `days` wären dann die
        // übrigen drei Tage statt der 428, die tatsächlich dazwischenliegen.
        func total(_ component: Calendar.Component) -> Int {
            calendar.dateComponents([component], from: start, to: end).value(for: component) ?? 0
        }

        return Span(
            seconds: end.timeIntervalSince(start),
            days: total(.day),
            workdays: workdays(from: start, to: end, calendar: calendar),
            weeks: total(.weekOfYear),
            months: total(.month),
            years: total(.year)
        )
    }

    /// Arbeitstage zwischen zwei Tagen, beide mitgezählt.
    ///
    /// Gerechnet und nicht gezählt: über ganze Wochen sind es fünf je Woche,
    /// und nur der Rest von weniger als einer Woche wird durchgegangen. Sonst
    /// liefe ein Abstand von zwanzig Jahren durch siebentausend Schleifen.
    public static func workdays(
        from start: Date,
        to end: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Int {
        let first = calendar.startOfDay(for: min(start, end))
        let last = calendar.startOfDay(for: max(start, end))
        guard let between = calendar.dateComponents([.day], from: first, to: last).day else { return 0 }

        let total = between + 1
        // `weekday` ist im gregorianischen Kalender immer 1 = Sonntag … 7 =
        // Samstag, unabhängig davon, welcher Tag in der Region die Woche
        // anfängt. Auf 0-basiert umgerechnet läuft der Rest mit `%` durch.
        let start0 = calendar.component(.weekday, from: first) - 1

        var count = (total / 7) * 5
        for step in 0..<(total % 7) {
            let day = (start0 + step) % 7
            // 0 = Sonntag, 6 = Samstag.
            if day != 0, day != 6 { count += 1 }
        }
        return end < start ? -count : count
    }

    /// Die Kalenderwoche nach ISO 8601 — die, die in Europa gemeint ist.
    ///
    /// Nicht `Calendar.current`: dort hängt die Wochenzählung an der Region,
    /// und in den USA fängt die Woche am Sonntag an. Eine Kalenderwoche, die
    /// je nach Systemeinstellung eine andere Zahl ergibt, ist keine.
    public static func isoWeek(of date: Date, in zone: TimeZone = .current) -> (week: Int, year: Int) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)
        return (parts.weekOfYear ?? 0, parts.yearForWeekOfYear ?? 0)
    }
}
