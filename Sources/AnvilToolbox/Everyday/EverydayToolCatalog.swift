import AnvilKit
import Foundation

/// The tools that have nothing to do with code.
///
/// Same engine as the converters in ``TextToolCatalog`` — a mode is a pure
/// function over a string — but a different audience: these are the ones you
/// reach for while writing an email, not while debugging.
///
/// Numbers are formatted with a full stop, never a comma. The result of a
/// conversion is something people paste on, and a comma turns into a thousands
/// separator the moment it lands in a spreadsheet.
public enum EverydayToolCatalog {
    public static var all: [TextTool] {
        [passwords, units, percent, timeZones, lorem]
    }

    // MARK: - Passwords

    static var passwords: TextTool {
        TextTool(
            id: "everyday.password",
            title: "Passwörter",
            subtitle: "Zufällig, ohne Verwechslungsgefahr",
            systemImage: "key.horizontal",
            category: .everyday,
            keywords: ["passwort", "password", "kennwort", "passphrase", "pin", "zufall", "generator"],
            isMonospaced: true,
            placeholder: "Braucht keine Eingabe — Variante rechts wählen.",
            generatesWithoutInput: true,
            modes: [
                TextToolMode(id: "strong16", title: "16 Zeichen", systemImage: "lock") { _ in
                    makePassword(length: 16, includesSymbols: true)
                },
                TextToolMode(id: "strong24", title: "24 Zeichen", systemImage: "lock.fill") { _ in
                    makePassword(length: 24, includesSymbols: true)
                },
                TextToolMode(id: "plain16", title: "Ohne Sonderzeichen", systemImage: "textformat") { _ in
                    makePassword(length: 16, includesSymbols: false)
                },
                TextToolMode(id: "passphrase", title: "Merkbare Wortfolge", systemImage: "text.word.spacing") { _ in
                    makePassphrase(words: 6)
                },
                TextToolMode(id: "pin", title: "PIN", systemImage: "number") { _ in
                    (0..<6).map { _ in String(Int.random(in: 0...9)) }.joined()
                },
                TextToolMode(id: "batch", title: "Zehn auf einmal", systemImage: "list.bullet") { _ in
                    (0..<10).map { _ in makePassword(length: 16, includesSymbols: true) }
                        .joined(separator: "\n")
                }
            ]
        )
    }

    /// Characters that cannot be mistaken for one another when read aloud or
    /// off a screen: no `0`/`O`, no `1`/`l`/`I`.
    private static let unambiguous = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let symbols = Array("!#$%&*+-=?@_")

    static func makePassword(length: Int, includesSymbols: Bool) -> String {
        let alphabet = includesSymbols ? unambiguous + symbols : unambiguous
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator) ?? "x" })
    }

    /// A passphrase from the list below: roughly 7 bits per word, so six words
    /// are about 42 bits — long enough for a login, not for a disk key.
    static func makePassphrase(words count: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        let picked = (0..<count).map { _ in passphraseWords.randomElement(using: &generator) ?? "anvil" }
        return picked.joined(separator: "-") + String(Int.random(in: 10...99))
    }

    // MARK: - Units

    static var units: TextTool {
        TextTool(
            id: "everyday.units",
            title: "Einheiten",
            subtitle: "Länge, Gewicht, Temperatur, Tempo, Daten",
            systemImage: "ruler",
            category: .everyday,
            keywords: [
                "einheiten", "umrechnen", "convert", "meter", "meilen", "kilo",
                "pfund", "celsius", "fahrenheit", "km/h", "mph", "gigabyte"
            ],
            isMonospaced: false,
            placeholder: "5 km in mi · 180 lb in kg · 72 °F in °C · 2 GiB in MB",
            modes: [
                TextToolMode(id: "convert", title: "Umrechnen", systemImage: "arrow.left.arrow.right") { input in
                    try convertUnits(input)
                },
                TextToolMode(id: "all", title: "In alle passenden", systemImage: "list.bullet") { input in
                    try convertToEveryUnit(input)
                }
            ]
        )
    }

    // MARK: - Percent

    static var percent: TextTool {
        TextTool(
            id: "everyday.percent",
            title: "Prozent",
            subtitle: "Anteil, Aufschlag, Veränderung",
            systemImage: "percent",
            category: .everyday,
            keywords: ["prozent", "percent", "rabatt", "aufschlag", "mehrwertsteuer", "mwst", "anteil"],
            isMonospaced: false,
            placeholder: "19% von 250 · 250 + 19% · von 250 auf 300 · 47.5 von 250",
            modes: [
                TextToolMode(id: "solve", title: "Rechnen", systemImage: "equal") { input in
                    try solvePercent(input)
                }
            ]
        )
    }

    // MARK: - Time zones

    static var timeZones: TextTool {
        TextTool(
            id: "everyday.timezones",
            title: "Zeitzonen",
            subtitle: "Wie spät ist es wo",
            systemImage: "globe.europe.africa",
            category: .everyday,
            keywords: ["zeitzone", "zeitzonen", "uhrzeit", "timezone", "utc", "meeting", "welt"],
            isMonospaced: true,
            placeholder: "Leer lassen für jetzt — oder eine Uhrzeit wie 14:30 eintragen.",
            generatesWithoutInput: true,
            modes: [
                TextToolMode(id: "now", title: "Jetzt", systemImage: "clock") { input in
                    worldClock(for: try referenceDate(from: input))
                }
            ]
        )
    }

    // MARK: - Lorem

    static var lorem: TextTool {
        TextTool(
            id: "everyday.lorem",
            title: "Blindtext",
            subtitle: "Platzhalter in der richtigen Länge",
            systemImage: "text.justify",
            category: .everyday,
            keywords: ["blindtext", "lorem", "ipsum", "platzhalter", "dummy", "fülltext"],
            isMonospaced: false,
            placeholder: "Braucht keine Eingabe — Länge rechts wählen.",
            generatesWithoutInput: true,
            modes: [
                TextToolMode(id: "sentence", title: "Ein Satz", systemImage: "text.append") { _ in
                    loremSentences(1)
                },
                TextToolMode(id: "paragraph", title: "Ein Absatz", systemImage: "text.alignleft") { _ in
                    loremSentences(5)
                },
                TextToolMode(id: "three", title: "Drei Absätze", systemImage: "text.justify") { _ in
                    (0..<3).map { _ in loremSentences(5) }.joined(separator: "\n\n")
                },
                TextToolMode(id: "list", title: "Fünf Stichpunkte", systemImage: "list.bullet") { _ in
                    (0..<5).map { _ in "- " + loremSentences(1) }.joined(separator: "\n")
                }
            ]
        )
    }

    // MARK: - Unit conversion

    /// One convertible quantity: the unit itself plus every spelling people
    /// actually type for it.
    struct UnitEntry {
        let unit: Dimension
        let symbol: String
        let names: [String]
        /// Groups units that can be converted into one another.
        let family: String
    }

    static let unitTable: [UnitEntry] = [
        // Länge
        UnitEntry(unit: UnitLength.millimeters, symbol: "mm", names: ["mm", "millimeter"], family: "Länge"),
        UnitEntry(unit: UnitLength.centimeters, symbol: "cm", names: ["cm", "zentimeter"], family: "Länge"),
        UnitEntry(unit: UnitLength.meters, symbol: "m", names: ["m", "meter"], family: "Länge"),
        UnitEntry(unit: UnitLength.kilometers, symbol: "km", names: ["km", "kilometer"], family: "Länge"),
        UnitEntry(unit: UnitLength.inches, symbol: "in", names: ["in", "inch", "zoll", "\""], family: "Länge"),
        UnitEntry(unit: UnitLength.feet, symbol: "ft", names: ["ft", "foot", "feet", "fuss"], family: "Länge"),
        UnitEntry(unit: UnitLength.yards, symbol: "yd", names: ["yd", "yard", "yards"], family: "Länge"),
        UnitEntry(unit: UnitLength.miles, symbol: "mi", names: ["mi", "mile", "miles", "meile", "meilen"], family: "Länge"),
        UnitEntry(unit: UnitLength.nauticalMiles, symbol: "nmi", names: ["nmi", "sm", "seemeile"], family: "Länge"),
        // Gewicht
        UnitEntry(unit: UnitMass.grams, symbol: "g", names: ["g", "gramm", "gram"], family: "Gewicht"),
        UnitEntry(unit: UnitMass.kilograms, symbol: "kg", names: ["kg", "kilo", "kilogramm"], family: "Gewicht"),
        UnitEntry(unit: UnitMass.metricTons, symbol: "t", names: ["t", "tonne", "tonnen"], family: "Gewicht"),
        UnitEntry(unit: UnitMass.ounces, symbol: "oz", names: ["oz", "unze", "unzen", "ounce"], family: "Gewicht"),
        UnitEntry(unit: UnitMass.pounds, symbol: "lb", names: ["lb", "lbs", "pfund", "pound", "pounds"], family: "Gewicht"),
        UnitEntry(unit: UnitMass.stones, symbol: "st", names: ["st", "stone", "stones"], family: "Gewicht"),
        // Temperatur
        UnitEntry(unit: UnitTemperature.celsius, symbol: "°C", names: ["c", "°c", "celsius"], family: "Temperatur"),
        UnitEntry(unit: UnitTemperature.fahrenheit, symbol: "°F", names: ["f", "°f", "fahrenheit"], family: "Temperatur"),
        UnitEntry(unit: UnitTemperature.kelvin, symbol: "K", names: ["k", "kelvin"], family: "Temperatur"),
        // Tempo
        UnitEntry(unit: UnitSpeed.kilometersPerHour, symbol: "km/h", names: ["kmh", "km/h", "kph"], family: "Tempo"),
        UnitEntry(unit: UnitSpeed.metersPerSecond, symbol: "m/s", names: ["ms", "m/s"], family: "Tempo"),
        UnitEntry(unit: UnitSpeed.milesPerHour, symbol: "mph", names: ["mph", "mp/h"], family: "Tempo"),
        UnitEntry(unit: UnitSpeed.knots, symbol: "kn", names: ["kn", "knoten", "knots"], family: "Tempo"),
        // Daten
        UnitEntry(unit: UnitInformationStorage.kilobytes, symbol: "kB", names: ["kb", "kilobyte"], family: "Daten"),
        UnitEntry(unit: UnitInformationStorage.megabytes, symbol: "MB", names: ["mb", "megabyte"], family: "Daten"),
        UnitEntry(unit: UnitInformationStorage.gigabytes, symbol: "GB", names: ["gb", "gigabyte"], family: "Daten"),
        UnitEntry(unit: UnitInformationStorage.terabytes, symbol: "TB", names: ["tb", "terabyte"], family: "Daten"),
        UnitEntry(unit: UnitInformationStorage.kibibytes, symbol: "KiB", names: ["kib", "kibibyte"], family: "Daten"),
        UnitEntry(unit: UnitInformationStorage.mebibytes, symbol: "MiB", names: ["mib", "mebibyte"], family: "Daten"),
        UnitEntry(unit: UnitInformationStorage.gibibytes, symbol: "GiB", names: ["gib", "gibibyte"], family: "Daten"),
        // Fläche
        UnitEntry(unit: UnitArea.squareMeters, symbol: "m²", names: ["m2", "m²", "quadratmeter"], family: "Fläche"),
        UnitEntry(unit: UnitArea.squareKilometers, symbol: "km²", names: ["km2", "km²"], family: "Fläche"),
        UnitEntry(unit: UnitArea.hectares, symbol: "ha", names: ["ha", "hektar"], family: "Fläche"),
        UnitEntry(unit: UnitArea.acres, symbol: "ac", names: ["ac", "acre", "acres"], family: "Fläche"),
        // Zeit
        UnitEntry(unit: UnitDuration.seconds, symbol: "s", names: ["s", "sek", "sekunde", "sekunden"], family: "Zeit"),
        UnitEntry(unit: UnitDuration.minutes, symbol: "min", names: ["min", "minute", "minuten"], family: "Zeit"),
        UnitEntry(unit: UnitDuration.hours, symbol: "h", names: ["h", "std", "stunde", "stunden"], family: "Zeit")
    ]

    /// `5 km in mi` and everything people type instead: `5km->mi`, `5 km nach
    /// mi`, `5,5 km to mi`.
    struct UnitRequest {
        var value: Double
        var source: UnitEntry
        var target: UnitEntry?
    }

    static func parseUnitRequest(_ input: String) throws -> UnitRequest {
        let normalised = input
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "->", with: " in ")
            .replacingOccurrences(of: "→", with: " in ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // The number may be glued to its unit ("5km"), so it is scanned off the
        // front rather than split on whitespace.
        var numberText = ""
        var rest = Substring(normalised)
        while let first = rest.first, first.isNumber || first == "." || first == "-" || first == "+" {
            numberText.append(first)
            rest = rest.dropFirst()
        }

        guard let value = Double(numberText) else {
            throw AnvilError.invalidInput(
                localized("Fang mit einer Zahl an, zum Beispiel „5 km in mi\".")
            )
        }

        let words = rest
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() }
            .filter { !["in", "to", "nach", "als"].contains($0) }

        guard let sourceName = words.first, let source = findUnit(sourceName) else {
            throw AnvilError.invalidInput(
                localized("Die Einheit hinter der Zahl kenne ich nicht.")
            )
        }

        guard words.count > 1 else { return UnitRequest(value: value, source: source, target: nil) }

        guard let target = findUnit(words[1]) else {
            throw AnvilError.invalidInput(localized("Die Zieleinheit kenne ich nicht."))
        }
        guard target.family == source.family else {
            throw AnvilError.invalidInput(
                localized("\(source.symbol) und \(target.symbol) lassen sich nicht ineinander umrechnen.")
            )
        }

        return UnitRequest(value: value, source: source, target: target)
    }

    private static func findUnit(_ name: String) -> UnitEntry? {
        let cleaned = name.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        return unitTable.first { entry in
            entry.names.contains(cleaned) || entry.symbol.lowercased() == cleaned
        }
    }

    static func convertUnits(_ input: String) throws -> String {
        let request = try parseUnitRequest(input)
        guard let target = request.target else {
            return try convertToEveryUnit(input)
        }

        let measurement = Measurement(value: request.value, unit: request.source.unit)
        let converted = measurement.converted(to: target.unit)
        return "\(formatNumber(converted.value)) \(target.symbol)"
    }

    static func convertToEveryUnit(_ input: String) throws -> String {
        let request = try parseUnitRequest(input)
        let measurement = Measurement(value: request.value, unit: request.source.unit)

        return unitTable
            .filter { $0.family == request.source.family && $0.symbol != request.source.symbol }
            .map { entry in
                let converted = measurement.converted(to: entry.unit)
                return "\(formatNumber(converted.value)) \(entry.symbol)"
            }
            .joined(separator: "\n")
    }

    // MARK: - Percent

    static func solvePercent(_ input: String) throws -> String {
        let text = input
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let numbers = text
            .split(whereSeparator: { !"0123456789.".contains($0) })
            .compactMap { Double($0) }

        guard numbers.count >= 2 else {
            throw AnvilError.invalidInput(
                localized("Zwei Zahlen bitte, zum Beispiel „19% von 250\".")
            )
        }

        let first = numbers[0]
        let second = numbers[1]

        // "von 250 auf 300" — the change between two values.
        if text.contains("auf") {
            guard first != 0 else {
                throw AnvilError.invalidInput(localized("Von null aus lässt sich keine Änderung berechnen."))
            }
            let change = (second - first) / first * 100
            let direction = change >= 0 ? "+" : ""
            return "\(direction)\(formatNumber(change))%"
        }

        // "250 + 19%" / "250 - 19%" — surcharge and discount.
        if text.contains("+") {
            return formatNumber(first * (1 + second / 100))
        }
        if text.contains("-") {
            return formatNumber(first * (1 - second / 100))
        }

        // "19% von 250" — the percent sign sits on the first number.
        if let percentIndex = text.firstIndex(of: "%"),
           let vonIndex = text.range(of: "von")?.lowerBound,
           percentIndex < vonIndex {
            return formatNumber(first / 100 * second)
        }

        // "47.5 von 250" — which share that is.
        guard second != 0 else {
            throw AnvilError.invalidInput(localized("Durch null lässt sich nicht teilen."))
        }
        return "\(formatNumber(first / second * 100))%"
    }

    // MARK: - Time zones

    /// The zones shown in the world clock. Deliberately a fixed list: a
    /// configurable one would need a settings screen for a tool whose whole
    /// point is that it answers in one glance.
    static let worldZones: [(city: String, identifier: String)] = [
        ("San Francisco", "America/Los_Angeles"),
        ("New York", "America/New_York"),
        ("London", "Europe/London"),
        ("Berlin", "Europe/Berlin"),
        ("Istanbul", "Europe/Istanbul"),
        ("Mumbai", "Asia/Kolkata"),
        ("Singapur", "Asia/Singapore"),
        ("Tokio", "Asia/Tokyo"),
        ("Sydney", "Australia/Sydney"),
        ("UTC", "UTC")
    ]

    /// Empty input means now; `14:30` means that time today, in the local zone.
    static func referenceDate(from input: String, now: Date = .now, calendar: Calendar = .current) throws -> Date {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return now }

        let parts = trimmed.split(separator: ":")
        guard let hour = Int(parts.first ?? ""), (0...23).contains(hour) else {
            throw AnvilError.invalidInput(localized("Uhrzeiten sehen so aus: 14:30."))
        }
        let minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        guard (0...59).contains(minute) else {
            throw AnvilError.invalidInput(localized("Uhrzeiten sehen so aus: 14:30."))
        }

        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
    }

    static func worldClock(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"

        // The date matters more than the hour when the answer is "tomorrow".
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "dd.MM."

        let width = worldZones.map(\.city.count).max() ?? 0

        return worldZones.map { city, identifier in
            guard let zone = TimeZone(identifier: identifier) else { return city }
            formatter.timeZone = zone
            dayFormatter.timeZone = zone

            let padded = city.padding(toLength: width, withPad: " ", startingAt: 0)
            return "\(padded)  \(formatter.string(from: date))  \(dayFormatter.string(from: date))"
        }
        .joined(separator: "\n")
    }

    // MARK: - Lorem

    static func loremSentences(_ count: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<count)
            .map { _ in
                let length = Int.random(in: 6...14, using: &generator)
                let words = (0..<length).map { _ in
                    loremWords.randomElement(using: &generator) ?? "lorem"
                }
                let sentence = words.joined(separator: " ")
                return sentence.prefix(1).uppercased() + sentence.dropFirst() + "."
            }
            .joined(separator: " ")
    }

    // MARK: - Formatting

    /// Six significant digits, no trailing zeros, always a full stop.
    static func formatNumber(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }

        var text = String(format: "%.6g", value)
        if text.contains("."), !text.contains("e") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    // MARK: - Word lists

    private static let passphraseWords = [
        "anker", "apfel", "atlas", "bahn", "berg", "biene", "birne", "blatt",
        "blume", "boot", "brief", "bruecke", "buch", "busch", "dach", "damm",
        "delfin", "donner", "dorf", "eiche", "eimer", "eisen", "engel", "ernte",
        "esel", "feder", "fels", "fenster", "feuer", "fisch", "flagge", "fluss",
        "garten", "gabel", "geige", "gipfel", "glas", "hafen", "hagel", "hammer",
        "hase", "haus", "heide", "himmel", "hirsch", "honig", "hut", "insel",
        "jacke", "kabel", "kaffee", "kamin", "kanu", "karte", "kerze", "kessel",
        "kiesel", "kirsche", "klee", "knopf", "koffer", "korb", "krone", "kueche",
        "lampe", "laterne", "leiter", "linde", "loewe", "luchs", "magnet", "mantel",
        "meer", "messer", "mond", "moos", "muschel", "nadel", "nebel", "nest",
        "nudel", "ofen", "orgel", "otter", "pfeil", "pflanze", "pinsel", "planke",
        "quelle", "rabe", "rakete", "regen", "reifen", "riegel", "ritter", "rose",
        "ruder", "sand", "schaf", "schere", "schiff", "schnee", "schuh", "segel",
        "seide", "spiegel", "stern", "stiefel", "strand", "strom", "tafel", "tanne",
        "taube", "teich", "teller", "tiger", "topf", "truhe", "tunnel", "turm",
        "uhr", "ufer", "vogel", "wagen", "wald", "welle", "wiese", "wolke",
        "wurzel", "zange", "zaun", "zebra", "ziegel", "zimmer", "zirkel", "zug"
    ]

    private static let loremWords = [
        "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing",
        "elit", "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore",
        "et", "dolore", "magna", "aliqua", "enim", "ad", "minim", "veniam",
        "quis", "nostrud", "exercitation", "ullamco", "laboris", "nisi", "aliquip",
        "ex", "ea", "commodo", "consequat", "duis", "aute", "irure", "in",
        "reprehenderit", "voluptate", "velit", "esse", "cillum", "eu", "fugiat",
        "nulla", "pariatur", "excepteur", "sint", "occaecat", "cupidatat", "non",
        "proident", "sunt", "culpa", "qui", "officia", "deserunt", "mollit",
        "anim", "id", "est", "laborum"
    ]
}
