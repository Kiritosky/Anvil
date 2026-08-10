import AnvilKit
import Foundation

/// Ein Umbenennen im Stapel — erst als Plan, dann als Tat.
///
/// Getrennt, weil Umbenennen nicht rückgängig zu machen ist, sobald es
/// passiert ist. Der Plan sagt vorher, was herauskäme, und **wo es klemmt**:
/// zwei Dateien mit demselben neuen Namen, ein Name, den es schon gibt, ein
/// Name, den das Dateisystem nicht nimmt. Erst wenn nichts davon übrig ist,
/// darf ausgeführt werden.
public struct RenamePlan: Sendable {
    // MARK: - Regeln

    /// Wie aus dem alten Namen ein neuer wird.
    ///
    /// Die Reihenfolge ist festgelegt und nicht einstellbar: erst suchen und
    /// ersetzen, dann die Vorlage, dann die Schreibweise. Einstellbar wäre sie
    /// nur scheinbar mächtiger — man müsste jedes Mal überlegen, was zuerst
    /// greift.
    public struct Rules: Sendable, Hashable {
        /// Was gesucht wird. Leer heißt: nichts ersetzen.
        public var search = ""
        public var replacement = ""
        public var isRegularExpression = false
        public var ignoresCase = false

        /// Die Vorlage für den neuen Namen.
        ///
        /// `{name}` ist der bisherige Name ohne Endung, `{ext}` die Endung,
        /// `{n}` die laufende Nummer, `{datum}` das heutige Datum. Leer heißt:
        /// den Namen so lassen, wie die Ersetzung ihn hinterlassen hat.
        public var pattern = ""

        /// Ab wo gezählt wird und wie breit die Nummer ist.
        public var counterStart = 1
        public var counterStep = 1
        public var counterWidth = 3

        public var casing = Casing.unchanged
        /// Leerzeichen durch dieses Zeichen ersetzen. Leer heißt: lassen.
        public var spaceReplacement = ""
        /// Eine neue Endung, ohne Punkt. Leer heißt: die alte behalten.
        public var newExtension = ""

        public init() {}

        public enum Casing: String, Hashable, Sendable, CaseIterable, Identifiable {
            case unchanged
            case lower
            case upper
            case capitalized

            public var id: String { rawValue }

            public var title: String {
                switch self {
                case .unchanged: localized("Unverändert")
                case .lower: localized("klein")
                case .upper: localized("GROSS")
                case .capitalized: localized("Wortanfänge groß")
                }
            }
        }
    }

    // MARK: - Was dabei herauskommt

    /// Was einem Eintrag im Weg steht.
    public enum Problem: String, Hashable, Sendable {
        /// Der neue Name ist der alte — nichts zu tun.
        case unchanged
        /// Nach allen Regeln bleibt nichts übrig.
        case empty
        /// Zwei Dateien im Stapel bekämen denselben Namen.
        case duplicate
        /// Der Name ist schon vergeben, und zwar von einer Datei außerhalb
        /// des Stapels.
        case occupied
        /// `/` und `:` gehen nicht — der eine trennt Pfade, der andere ist im
        /// Finder das, was der Schrägstrich auf der Platte ist.
        case invalidCharacter

        public var title: String {
            switch self {
            case .unchanged: localized("Unverändert")
            case .empty: localized("Name wäre leer")
            case .duplicate: localized("Name doppelt im Stapel")
            case .occupied: localized("Name schon vergeben")
            case .invalidCharacter: localized("Zeichen nicht erlaubt")
            }
        }

        /// Ob der Eintrag deshalb nicht ausgeführt wird.
        ///
        /// „Unverändert" ist kein Fehler, sondern eine Datei, die einfach
        /// bleibt, wo sie ist.
        public var isBlocking: Bool { self != .unchanged }
    }

    public struct Entry: Sendable, Identifiable {
        public let id: Int
        public let url: URL
        public let currentName: String
        public let newName: String
        public let problem: Problem?

        public var willChange: Bool { problem == nil }
        public var destination: URL {
            url.deletingLastPathComponent().appendingPathComponent(newName)
        }
    }

    public let entries: [Entry]

    public var changing: [Entry] { entries.filter(\.willChange) }
    public var blocked: [Entry] { entries.filter { $0.problem?.isBlocking == true } }
    public var isReady: Bool { !changing.isEmpty && blocked.isEmpty }

    // MARK: - Planen

    /// Baut den Plan.
    ///
    /// - Parameter existingNames: Was im Ordner sonst noch liegt. Wird es
    ///   nicht mitgegeben, kann der Plan nicht sehen, dass ein Name schon
    ///   vergeben ist — und genau das fällt sonst erst beim Ausführen auf,
    ///   wenn die Hälfte schon umbenannt ist.
    public init(files: [URL], rules: Rules, existingNames: Set<String> = []) {
        var entries: [Entry] = []
        var seen: [String: Int] = [:]
        var counter = rules.counterStart

        // Die Namen des Stapels selbst zählen nicht als vergeben: eine Datei
        // darf den Namen einer anderen bekommen, wenn die ihn abgibt.
        let ownNames = Set(files.map { $0.lastPathComponent })
        let foreign = existingNames.subtracting(ownNames)

        for (index, url) in files.enumerated() {
            let currentName = url.lastPathComponent
            let newName = Self.name(
                for: url,
                rules: rules,
                index: index,
                counter: counter,
                today: Self.today
            )
            counter += rules.counterStep

            let problem: Problem?
            if newName.isEmpty || newName == "." {
                problem = .empty
            } else if newName.contains("/") || newName.contains(":") {
                problem = .invalidCharacter
            } else if newName == currentName {
                problem = .unchanged
            } else if let first = seen[newName], first != index {
                problem = .duplicate
            } else if foreign.contains(newName) {
                problem = .occupied
            } else {
                problem = nil
            }

            seen[newName] = seen[newName] ?? index
            entries.append(
                Entry(
                    id: index,
                    url: url,
                    currentName: currentName,
                    newName: newName,
                    problem: problem
                )
            )
        }

        // Der erste von zwei gleichen Namen merkt beim Bauen noch nichts —
        // der Doppelte kommt erst danach. Also im zweiten Durchgang beide
        // markieren.
        var counts: [String: Int] = [:]
        for entry in entries { counts[entry.newName, default: 0] += 1 }
        self.entries = entries.map { entry in
            guard counts[entry.newName, default: 0] > 1, entry.problem == nil else { return entry }
            return Entry(
                id: entry.id,
                url: entry.url,
                currentName: entry.currentName,
                newName: entry.newName,
                problem: .duplicate
            )
        }
    }

    /// Das heutige Datum als `2026-08-10`.
    static var today: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Der neue Name

    static func name(
        for url: URL,
        rules: Rules,
        index: Int,
        counter: Int,
        today: String
    ) -> String {
        var stem = url.deletingPathExtension().lastPathComponent
        let originalExtension = url.pathExtension

        if !rules.search.isEmpty {
            stem = replace(in: stem, rules: rules)
        }

        if !rules.pattern.isEmpty {
            stem = rules.pattern
                .replacingOccurrences(of: "{name}", with: stem)
                .replacingOccurrences(of: "{n}", with: number(counter, width: rules.counterWidth))
                .replacingOccurrences(of: "{datum}", with: today)
                .replacingOccurrences(of: "{date}", with: today)
                .replacingOccurrences(of: "{ext}", with: originalExtension)
        }

        if !rules.spaceReplacement.isEmpty {
            stem = stem.replacingOccurrences(of: " ", with: rules.spaceReplacement)
        }

        switch rules.casing {
        case .unchanged: break
        case .lower: stem = stem.lowercased()
        case .upper: stem = stem.uppercased()
        case .capitalized: stem = stem.capitalized
        }

        let suffix = rules.newExtension.isEmpty ? originalExtension : rules.newExtension
        return suffix.isEmpty ? stem : "\(stem).\(suffix)"
    }

    /// Ersetzen — wörtlich oder als regulärer Ausdruck.
    ///
    /// Ein fehlerhaftes Muster lässt den Namen unverändert, statt zu werfen:
    /// Beim Tippen eines Ausdrucks ist er die meiste Zeit unfertig, und ein
    /// Fehler bei jedem Tastendruck hilft niemandem.
    static func replace(in text: String, rules: Rules) -> String {
        guard rules.isRegularExpression else {
            return text.replacingOccurrences(
                of: rules.search,
                with: rules.replacement,
                options: rules.ignoresCase ? [.caseInsensitive] : []
            )
        }

        var options: NSRegularExpression.Options = []
        if rules.ignoresCase { options.insert(.caseInsensitive) }
        guard let expression = try? NSRegularExpression(pattern: rules.search, options: options) else {
            return text
        }
        return expression.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: rules.replacement
        )
    }

    static func number(_ value: Int, width: Int) -> String {
        let digits = String(abs(value))
        let padding = max(0, width - digits.count)
        return (value < 0 ? "-" : "") + String(repeating: "0", count: padding) + digits
    }

    // MARK: - Ausführen

    /// Was getan wurde — und wie es sich zurücknehmen ließe.
    public struct Outcome: Sendable {
        public let renamed: Int
        /// Von neu nach alt, für den Weg zurück.
        public let undo: [(from: URL, to: URL)]
    }

    /// Führt den Plan aus.
    ///
    /// In zwei Durchgängen über Zwischennamen. Der Grund ist der Tausch: Soll
    /// `a` zu `b` und `b` zu `a` werden, überschreibt der erste Schritt in
    /// einem Durchgang die zweite Datei. Über Zwischennamen kann das nicht
    /// passieren, egal in welcher Reihenfolge die Dateien stehen.
    @discardableResult
    public func execute(using manager: FileManager = .default) throws -> Outcome {
        guard isReady else {
            throw AnvilError.invalidInput(
                localized("Erst muss jeder Eintrag in Ordnung sein. Ausgeführt wird nur ein Plan ohne Beanstandung.")
            )
        }

        let work = changing
        let token = UUID().uuidString.prefix(8)
        var temporary: [(url: URL, destination: URL)] = []

        for entry in work {
            let stopgap = entry.url
                .deletingLastPathComponent()
                .appendingPathComponent("\(token)-\(entry.id)-\(entry.newName)")
            try manager.moveItem(at: entry.url, to: stopgap)
            temporary.append((stopgap, entry.destination))
        }

        for step in temporary {
            try manager.moveItem(at: step.url, to: step.destination)
        }

        // Der Rückweg führt auf den ursprünglichen Namen, nicht auf den
        // Zwischennamen.
        let undo = work.map { (from: $0.destination, to: $0.url) }
        return Outcome(renamed: work.count, undo: undo)
    }
}
