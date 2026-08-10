import AnvilKit
import Foundation

/// Testdaten, die jedes Mal dieselben sind.
///
/// Der Punkt ist der Startwert. Zufällige Testdaten sind für einen Screenshot
/// gut und für alles andere schlecht: Ein Fehler, der bei „Müller" auftritt und
/// bei „Schmidt" nicht, ist nicht wiederfindbar, wenn beim nächsten Lauf ganz
/// andere Namen herauskommen. Hier ergibt derselbe Startwert dieselbe Tabelle
/// — auf einem anderen Rechner, in einem Jahr, in jeder Reihenfolge.
public struct SampleData: Sendable {
    // MARK: - Was erzeugt wird

    public enum Field: String, Hashable, Sendable, CaseIterable, Identifiable {
        case id
        case firstName
        case lastName
        case fullName
        case email
        case company
        case street
        case postalCode
        case city
        case country
        case phone
        case iban
        case date
        case uuid
        case sentence
        case amount
        case boolean

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .id: localized("Nummer")
            case .firstName: localized("Vorname")
            case .lastName: localized("Nachname")
            case .fullName: localized("Name")
            case .email: localized("E-Mail")
            case .company: localized("Firma")
            case .street: localized("Straße")
            case .postalCode: localized("PLZ")
            case .city: localized("Ort")
            case .country: localized("Land")
            case .phone: localized("Telefon")
            case .iban: "IBAN"
            case .date: localized("Datum")
            case .uuid: "UUID"
            case .sentence: localized("Satz")
            case .amount: localized("Betrag")
            case .boolean: localized("Ja/Nein")
            }
        }

        /// Was standardmäßig angehakt ist: genug für eine Adressliste, wenig
        /// genug, dass die Tabelle auf den Schirm passt.
        public static let common: [Field] = [.id, .fullName, .email, .city, .amount]
    }

    /// Aus welchem Sprachraum die Namen kommen.
    public enum Region: String, Hashable, Sendable, CaseIterable, Identifiable {
        case german
        case english

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .german: localized("Deutsch")
            case .english: localized("Englisch")
            }
        }
    }

    // MARK: - Der Zufall, der keiner ist

    /// SplitMix64 — klein, schnell, und bei gleichem Startwert überall gleich.
    ///
    /// `SystemRandomNumberGenerator` wäre einfacher und genau das Falsche: es
    /// gibt keinen Startwert, also auch keine Wiederholbarkeit.
    struct Generator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            // Ein Startwert von 0 ist erlaubt und ergibt trotzdem eine Folge.
            state = seed &+ 0x9E37_79B9_7F4A_7C15
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    // MARK: - Erzeugen

    public let fields: [Field]
    public let region: Region
    public let seed: UInt64
    public let rows: [[String]]

    public init(count: Int, fields: [Field], region: Region = .german, seed: UInt64 = 1) {
        let fields = fields.isEmpty ? Field.common : fields
        self.fields = fields
        self.region = region
        self.seed = seed

        var generator = Generator(seed: seed)
        var rows: [[String]] = []
        rows.reserveCapacity(max(0, count))

        for index in 0..<max(0, count) {
            rows.append(Self.row(index: index, fields: fields, region: region, using: &generator))
        }
        self.rows = rows
    }

    /// Eine Zeile.
    ///
    /// Die Felder hängen voneinander ab: Die E-Mail-Adresse gehört zum Namen,
    /// und die Postleitzahl zum Ort. Testdaten, bei denen „Anna Müller" die
    /// Adresse `heinz.schulz@…` hat, fallen beim ersten Blick auf und taugen
    /// für keine Vorführung.
    private static func row(
        index: Int,
        fields: [Field],
        region: Region,
        using generator: inout Generator
    ) -> [String] {
        let names = region == .german ? germanFirstNames : englishFirstNames
        let surnames = region == .german ? germanLastNames : englishLastNames
        let places = region == .german ? germanCities : englishCities
        let roads = region == .german ? germanStreets : englishStreets

        let firstName = names.randomElement(using: &generator) ?? "Anna"
        let lastName = surnames.randomElement(using: &generator) ?? "Meier"
        let city = places.randomElement(using: &generator) ?? "Bremen"
        let company = companies.randomElement(using: &generator) ?? "Kontur"
        let suffix = companySuffixes.randomElement(using: &generator) ?? "GmbH"
        let street = roads.randomElement(using: &generator) ?? "Hauptstraße"
        let houseNumber = Int.random(in: 1...199, using: &generator)
        let postalCode = String(format: "%05d", Int.random(in: 1000...99999, using: &generator))
        let amount = Double(Int.random(in: 100...500_000, using: &generator)) / 100
        let day = Int.random(in: 1...28, using: &generator)
        let month = Int.random(in: 1...12, using: &generator)
        let year = Int.random(in: 2020...2026, using: &generator)
        let bank = Int.random(in: 10_000_000...99_999_999, using: &generator)
        let account = Int.random(in: 100_000_000...9_999_999_999, using: &generator)
        let phone = Int.random(in: 1_000_000...9_999_999, using: &generator)
        let area = Int.random(in: 30...899, using: &generator)
        let sentence = Self.sentence(using: &generator)
        let flag = Bool.random(using: &generator)

        return fields.map { field in
            switch field {
            case .id: "\(index + 1)"
            case .firstName: firstName
            case .lastName: lastName
            case .fullName: "\(firstName) \(lastName)"
            case .email: Self.email(firstName: firstName, lastName: lastName, company: company)
            case .company: "\(company) \(suffix)"
            case .street: "\(street) \(houseNumber)"
            case .postalCode: postalCode
            case .city: city
            case .country: region == .german ? localized("Deutschland") : localized("Vereinigtes Königreich")
            case .phone: region == .german ? "+49 \(area) \(phone)" : "+44 \(area) \(phone)"
            case .iban: Self.germanIBAN(bank: bank, account: account)
            case .date: String(format: "%04d-%02d-%02d", year, month, day)
            case .uuid: Self.uuid(using: &generator)
            case .sentence: sentence
            case .amount: String(format: "%.2f", amount).replacingOccurrences(of: ".", with: ",")
            case .boolean: flag ? localized("ja") : localized("nein")
            }
        }
    }

    // MARK: - Einzelne Felder

    /// Eine Adresse, die zum Namen passt — ohne Umlaute und ohne ß, weil die
    /// im lokalen Teil einer Adresse nichts zu suchen haben.
    static func email(firstName: String, lastName: String, company: String) -> String {
        let local = "\(firstName).\(lastName)".lowercased()
        let clean = local
            .replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue")
            .replacingOccurrences(of: "ß", with: "ss")
            .filter { $0.isASCII && ($0.isLetter || $0 == ".") }
        let domain = company.lowercased().filter { $0.isASCII && $0.isLetter }
        return "\(clean)@\(domain).example"
    }

    /// Eine deutsche IBAN mit richtiger Prüfziffer.
    ///
    /// Eine Prüfziffer zu erfinden wäre einfacher und wertlos: Testdaten
    /// braucht man gerade dort, wo eine Prüfung läuft — sonst prüft der Test
    /// nur, dass die Prüfung ablehnt.
    public static func germanIBAN(bank: Int, account: Int) -> String {
        let bban = String(format: "%08d%010d", bank, account)
        // DE00 ans Ende, D → 13, E → 14, dann Rest 98 − (Zahl mod 97).
        let rearranged = bban + "131400"
        let check = 98 - mod97(rearranged)
        return String(format: "DE%02d", check) + bban
    }

    /// `mod 97` für eine Zahl, die in keine Ganzzahl passt.
    ///
    /// Ziffernweise: Der Rest bleibt immer klein genug, egal wie lang die Zahl
    /// ist. Eine IBAN hat bis zu 34 Stellen — kein `UInt64` fasst das.
    static func mod97(_ digits: String) -> Int {
        var remainder = 0
        for character in digits {
            guard let value = character.wholeNumberValue else { continue }
            remainder = (remainder * 10 + value) % 97
        }
        return remainder
    }

    /// Eine UUID aus demselben Startwert.
    ///
    /// `UUID()` wäre echt zufällig und damit bei jedem Lauf anders — genau
    /// das, was hier nicht sein soll.
    static func uuid(using generator: inout Generator) -> String {
        var bytes: [UInt8] = []
        for _ in 0..<2 {
            let value = generator.next()
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
            }
        }
        // Fassung 4, Variante 1 — sonst ist es keine UUID, sondern nur hübsch.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let groups = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { range in
            String(Array(hex)[range])
        }
        return groups.joined(separator: "-")
    }

    static func sentence(using generator: inout Generator) -> String {
        let count = Int.random(in: 4...10, using: &generator)
        var words: [String] = []
        for _ in 0..<count {
            words.append(sentenceWords.randomElement(using: &generator) ?? "Kontur")
        }
        let first = words[0].prefix(1).uppercased() + words[0].dropFirst()
        return ([first] + words.dropFirst()).joined(separator: " ") + "."
    }

    // MARK: - Ausgeben

    /// Die Daten als Tabelle — damit alles, was die Tabellen können, auch für
    /// Testdaten gilt: JSON, Markdown, SQL, jedes Trennzeichen.
    public var table: CSVTable {
        CSVTable(
            parsing: ([fields.map(\.title)] + rows)
                .map { row in row.map(Self.quoted).joined(separator: "\t") }
                .joined(separator: "\n"),
            delimiter: .tab,
            hasHeader: true
        )
    }

    private static func quoted(_ field: String) -> String {
        field.contains("\t") || field.contains("\"")
            ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : field
    }

    // MARK: - Wortlisten

    static let germanFirstNames = [
        "Anna", "Ben", "Clara", "David", "Emma", "Felix", "Greta", "Hannes",
        "Ida", "Jonas", "Katharina", "Lukas", "Marie", "Niklas", "Olivia",
        "Paul", "Rosa", "Simon", "Theresa", "Vincent"
    ]

    static let germanLastNames = [
        "Müller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer", "Wagner",
        "Becker", "Hoffmann", "Schäfer", "Koch", "Bauer", "Richter", "Klein",
        "Wolf", "Neumann", "Schwarz", "Zimmermann", "Braun", "Krüger"
    ]

    static let englishFirstNames = [
        "Alice", "Ben", "Chloe", "Daniel", "Ella", "Finn", "Grace", "Harry",
        "Isla", "Jack", "Kate", "Liam", "Maya", "Noah", "Olive",
        "Peter", "Rosie", "Sam", "Tessa", "Vera"
    ]

    static let englishLastNames = [
        "Smith", "Jones", "Taylor", "Brown", "Wilson", "Evans", "Thomas",
        "Roberts", "Walker", "Wright", "Green", "Hall", "Wood", "Clarke",
        "Harris", "Turner", "Hill", "Ward", "Baker", "Cooper"
    ]

    static let germanCities = [
        "Bremen", "Kiel", "Aachen", "Leipzig", "Erfurt", "Rostock", "Trier",
        "Passau", "Ulm", "Kassel", "Jena", "Lübeck", "Bonn", "Mainz", "Fulda"
    ]

    static let englishCities = [
        "Bristol", "Leeds", "York", "Bath", "Derby", "Exeter", "Norwich",
        "Oxford", "Durham", "Chester", "Ely", "Truro", "Ripon", "Wells", "Lincoln"
    ]

    static let germanStreets = [
        "Hauptstraße", "Bahnhofstraße", "Lindenweg", "Am Markt", "Kirchgasse",
        "Schulstraße", "Gartenweg", "Mühlenweg", "Ringstraße", "Feldweg"
    ]

    static let englishStreets = [
        "High Street", "Station Road", "Church Lane", "Mill Road", "Park Avenue",
        "Victoria Street", "Queens Road", "Market Place", "School Lane", "Field Way"
    ]

    static let companies = [
        "Kontur", "Nordlicht", "Wegmarke", "Silbergrund", "Hafenblick",
        "Steinbruch", "Klarwerk", "Feinschliff", "Weitwinkel", "Ankerplatz"
    ]

    static let companySuffixes = ["GmbH", "AG", "KG", "e. K.", "GmbH & Co. KG"]

    static let sentenceWords = [
        "Anvil", "Werkzeug", "Fenster", "Eingabe", "Ergebnis", "Tabelle",
        "Ordner", "Vorlage", "Abschnitt", "Zeile", "Wert", "Prüfung",
        "Muster", "Ablage", "Auswahl", "Bericht", "Notiz", "Entwurf"
    ]
}
