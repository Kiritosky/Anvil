import AnvilKit
import Foundation

// MARK: - Zahlen, die größer sind als die Maschine

/// Rechnerei, die nicht in eine Ganzzahl passt.
///
/// Ein IPv6-Netz mit /0 hat 2^128 Adressen. Keine Ganzzahl dieses Rechners
/// fasst das, und trotzdem ist die Zahl das, was der Benutzer sehen will —
/// also entsteht sie Ziffer für Ziffer.
public enum IPMath {
    /// 2^`exponent` als Dezimalzahl.
    ///
    /// Fortgesetztes Verdoppeln einer Ziffernliste: langsam, aber exakt, und
    /// bei höchstens 128 Verdopplungen schnell genug für jede Tastatureingabe.
    public static func powerOfTwo(_ exponent: Int) -> String {
        guard exponent > 0 else { return "1" }
        // Niederwertigste Ziffer zuerst — so wächst die Liste hinten, und der
        // Übertrag läuft in Leserichtung des Algorithmus.
        var digits = [1]
        for _ in 0..<exponent {
            var carry = 0
            for index in digits.indices {
                let doubled = digits[index] * 2 + carry
                digits[index] = doubled % 10
                carry = doubled / 10
            }
            if carry > 0 { digits.append(carry) }
        }
        return digits.reversed().map { String($0) }.joined()
    }

    /// Setzt schmale Leerzeichen in Dreierblöcke.
    ///
    /// Ein Punkt als Tausendertrenner wäre in einem Werkzeug, das den ganzen
    /// Tag Adressen mit Punkten zeigt, die schlechteste aller Ideen. Das
    /// schmale geschützte Leerzeichen trennt, ohne eine neue Bedeutung
    /// mitzubringen, und bricht die Zahl nicht um.
    public static func grouped(_ digits: String) -> String {
        guard digits.count > 4 else { return digits }
        var result = ""
        for (offset, character) in digits.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 { result.append("\u{202F}") }
            result.append(character)
        }
        return String(result.reversed())
    }
}

// MARK: - Familie

/// IPv4 oder IPv6.
public enum IPFamily: String, Hashable, Sendable, CaseIterable {
    case v4
    case v6

    /// Protokollnamen werden in keiner Sprache übersetzt.
    public var title: String {
        self == .v4 ? "IPv4" : "IPv6"
    }

    /// Die größte erlaubte Präfixlänge.
    public var maximumPrefixLength: Int {
        self == .v4 ? 32 : 128
    }
}

// MARK: - IPv4

/// Eine IPv4-Adresse — 32 Bit, nicht vier Zeichenketten.
///
/// Alles, was dieses Werkzeug rechnet, ist Bitarbeit: maskieren, invertieren,
/// hochzählen. Auf Zeichenketten wäre jede dieser Operationen eine
/// Fehlerquelle, also wird genau einmal beim Lesen und genau einmal beim
/// Anzeigen umgewandelt.
public struct IPv4Address: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let value: UInt32

    public init(_ value: UInt32) {
        self.value = value
    }

    public init(parsing text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Ohne `omittingEmptySubsequences: false` verschwänden „1..2.3" und
        // „1.2.3." lautlos in einer gültigen Adresse.
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { throw Self.notAnAddress(text) }

        var result: UInt32 = 0
        for part in parts {
            guard !part.isEmpty,
                  part.count <= 3,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let octet = UInt32(part),
                  octet <= 255
            else { throw Self.notAnAddress(text) }
            result = (result << 8) | octet
        }
        self.value = result
    }

    public var text: String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }

    public var description: String { text }

    public static func < (lhs: IPv4Address, rhs: IPv4Address) -> Bool {
        lhs.value < rhs.value
    }

    static func notAnAddress(_ text: String) -> AnvilError {
        AnvilError.invalidInput(localized("Das ist keine IPv4-Adresse: \(text)"))
    }
}

/// Ein IPv4-Netz: eine Adresse und die Zahl der festgelegten Bits.
public struct IPv4Network: Hashable, Sendable, CustomStringConvertible {
    /// Die Adresse, wie sie eingegeben wurde — mit Hostbits, wenn welche
    /// gesetzt waren. Das Netz selbst steht in ``networkAddress``.
    public let address: IPv4Address
    public let prefixLength: Int

    /// Für den internen Gebrauch, wenn die Präfixlänge nachweislich stimmt.
    init(_ address: IPv4Address, prefixLength: Int) {
        self.address = address
        self.prefixLength = prefixLength
    }

    public init(address: IPv4Address, prefixLength: Int) throws {
        guard (0...32).contains(prefixLength) else {
            throw AnvilError.invalidInput(
                localized("Eine IPv4-Präfixlänge liegt zwischen 0 und 32.")
            )
        }
        self.init(address, prefixLength: prefixLength)
    }

    /// Liest „192.168.1.0/24", „192.168.1.0/255.255.255.0",
    /// „192.168.1.0 255.255.255.0" und die nackte Adresse als /32.
    public init(parsing text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AnvilError.invalidInput(localized("Da steht noch keine Adresse."))
        }

        let parts = trimmed
            .split(whereSeparator: { $0 == "/" || $0.isWhitespace })
            .map(String.init)
        guard let addressPart = parts.first, parts.count <= 2 else {
            throw AnvilError.invalidInput(
                localized("Ein Netz besteht aus einer Adresse und höchstens einer Angabe dahinter: \(text)")
            )
        }

        let address = try IPv4Address(parsing: addressPart)
        guard parts.count == 2 else {
            // Ohne Angabe dahinter ist genau diese eine Adresse gemeint.
            try self.init(address: address, prefixLength: 32)
            return
        }

        let suffix = parts[1]
        if suffix.contains(".") {
            let written = try IPv4Address(parsing: suffix)
            // Cisco-Zugriffslisten schreiben die Maske andersherum. Wer eine
            // Wildcard einträgt, meint dasselbe Netz — also beides versuchen.
            guard let prefixLength = Self.prefixLength(mask: written.value)
                ?? Self.prefixLength(mask: ~written.value)
            else {
                throw AnvilError.invalidInput(
                    localized("Diese Maske hat Lücken — Einsen und Nullen müssen zusammenhängen: \(suffix)")
                )
            }
            try self.init(address: address, prefixLength: prefixLength)
        } else {
            guard let prefixLength = Int(suffix) else {
                throw AnvilError.invalidInput(
                    localized("Hinter dem Schrägstrich steht eine Präfixlänge oder eine Maske: \(suffix)")
                )
            }
            try self.init(address: address, prefixLength: prefixLength)
        }
    }

    // MARK: Maske und Präfix

    /// Die Präfixlänge zu einer Maske — oder `nil`, wenn die Maske Lücken hat.
    ///
    /// Eine gültige Maske ist eine ununterbrochene Folge von Einsen, gefolgt
    /// von einer ununterbrochenen Folge von Nullen. Gezählt werden deshalb die
    /// Nullbits, und geprüft wird, ob die daraus gebaute Maske dieselbe ist.
    public static func prefixLength(mask value: UInt32) -> Int? {
        let hostBits = (~value).nonzeroBitCount
        return (UInt32.max << hostBits) == value ? 32 - hostBits : nil
    }

    public var mask: IPv4Address {
        // Swifts `<<` ist ein „smart shift": um 32 verschoben ergibt es 0 und
        // nicht undefiniertes Verhalten — genau das, was /0 braucht.
        IPv4Address(UInt32.max << (32 - prefixLength))
    }

    public var wildcard: IPv4Address { IPv4Address(~mask.value) }

    /// Die erste Adresse des Netzes. Gesetzte Hostbits fallen hier weg — aus
    /// 192.168.1.5/24 wird 192.168.1.0.
    public var networkAddress: IPv4Address { IPv4Address(address.value & mask.value) }

    /// Die letzte Adresse des Netzes.
    public var lastAddress: IPv4Address { IPv4Address(networkAddress.value | wildcard.value) }

    /// Wie viele Adressen im Netz stehen — bei /0 sind es 2^32, also mehr, als
    /// in einen `UInt32` passt.
    public var addressCount: UInt64 { UInt64(1) << (32 - prefixLength) }

    /// Ein Netz aus genau einer Adresse.
    public var isHostRoute: Bool { prefixLength == 32 }

    /// Punkt-zu-Punkt nach RFC 3021: zwei Adressen, beide benutzbar, keine
    /// davon Netz- oder Broadcast-Adresse.
    public var isPointToPoint: Bool { prefixLength == 31 }

    /// Ab /31 gibt es keine Broadcast-Adresse mehr.
    public var broadcastAddress: IPv4Address? {
        prefixLength <= 30 ? lastAddress : nil
    }

    /// Der klassische Hostbereich — Netz- und Broadcast-Adresse abgezogen.
    ///
    /// Bei /31 und /32 gibt es ihn nicht. Das ist der Grund, warum hier
    /// überhaupt Optionale stehen: `addressCount - 2` wäre bei einem /32 ein
    /// Unterlauf, und eine Zahl in der Nähe von 18 Trillionen ist eine
    /// schlechtere Antwort als „gibt es nicht".
    public var firstUsableAddress: IPv4Address? {
        prefixLength <= 30 ? IPv4Address(networkAddress.value + 1) : nil
    }

    public var lastUsableAddress: IPv4Address? {
        prefixLength <= 30 ? IPv4Address(lastAddress.value - 1) : nil
    }

    public var usableHostCount: UInt64 {
        prefixLength <= 30 ? addressCount - 2 : 0
    }

    /// Was an diesem Netz besonders ist, in einem Satz.
    public var note: String? {
        if isHostRoute {
            return localized("Genau eine Adresse — ein einzelner Host, kein Netz mit Hostbereich.")
        }
        if isPointToPoint {
            return localized("Punkt-zu-Punkt nach RFC 3021: beide Adressen sind benutzbar, es gibt keinen Broadcast.")
        }
        return nil
    }

    public var scope: IPScope { IPScope.of(networkAddress) }

    public func contains(_ candidate: IPv4Address) -> Bool {
        candidate.value & mask.value == networkAddress.value
    }

    /// Das Netz in Normalform: Hostbits weg, Präfixlänge dahinter.
    public var description: String { "\(networkAddress.text)/\(prefixLength)" }

    // MARK: Teilen

    private func validateSplit(_ newPrefixLength: Int) throws {
        guard (0...32).contains(newPrefixLength) else {
            throw AnvilError.invalidInput(
                localized("Eine IPv4-Präfixlänge liegt zwischen 0 und 32.")
            )
        }
        guard newPrefixLength >= prefixLength else {
            throw AnvilError.invalidInput(
                localized("Ein Teilnetz kann nicht größer sein als das Netz, aus dem es kommt.")
            )
        }
    }

    /// Wie viele Teilnetze mit `newPrefixLength` in dieses Netz passen.
    public func subnetCount(splittingInto newPrefixLength: Int) throws -> UInt64 {
        try validateSplit(newPrefixLength)
        return UInt64(1) << (newPrefixLength - prefixLength)
    }

    /// Die ersten `limit` Teilnetze.
    ///
    /// Gekappt, weil ein /8 in /30 zerlegt über vier Millionen Zeilen wären —
    /// eine Liste, die niemand liest und die das Fenster für Sekunden anhält.
    public func split(into newPrefixLength: Int, limit: Int = 64) throws -> [IPv4Network] {
        let count = try subnetCount(splittingInto: newPrefixLength)
        let step = UInt64(1) << (32 - newPrefixLength)
        let base = UInt64(networkAddress.value)
        let shown = min(count, UInt64(max(limit, 0)))
        return (0..<shown).map { index in
            IPv4Network(
                IPv4Address(UInt32(base + index * step)),
                prefixLength: newPrefixLength
            )
        }
    }
}

// MARK: - IPv6

/// Eine IPv6-Adresse als zwei mal 64 Bit.
///
/// Sechzehn Bytes wären dasselbe, aber zwei `UInt64` lassen sich maskieren und
/// addieren, ohne über ein Array zu laufen.
public struct IPv6Address: Hashable, Sendable, CustomStringConvertible {
    public let high: UInt64
    public let low: UInt64

    public init(high: UInt64, low: UInt64) {
        self.high = high
        self.low = low
    }

    /// Aus acht Blöcken. Fehlende Blöcke gelten als Null, überzählige fallen
    /// weg — die Prüfung, dass es genau acht sind, gehört zum Lesen.
    init(groups: [UInt16]) {
        let padded = groups + Array(repeating: 0, count: max(0, 8 - groups.count))
        var high: UInt64 = 0
        var low: UInt64 = 0
        for (index, group) in padded.prefix(8).enumerated() {
            if index < 4 {
                high = (high << 16) | UInt64(group)
            } else {
                low = (low << 16) | UInt64(group)
            }
        }
        self.init(high: high, low: low)
    }

    public init(parsing text: String) throws {
        var work = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Ein Zonenindex gehört zur Schnittstelle, nicht zur Adresse.
        if let percent = work.firstIndex(of: "%") {
            work = String(work[work.startIndex..<percent])
        }
        // Eckige Klammern stehen in URLs um die Adresse herum.
        if work.hasPrefix("["), work.hasSuffix("]"), work.count >= 2 {
            work = String(work.dropFirst().dropLast())
        }
        guard !work.isEmpty else { throw Self.notAnAddress(text) }

        let halves = work.components(separatedBy: "::")
        guard halves.count <= 2 else {
            throw AnvilError.invalidInput(
                localized("In einer IPv6-Adresse darf höchstens einmal :: stehen: \(text)")
            )
        }

        let head = try Self.parseGroups(in: halves[0], of: text)
        let tail = halves.count == 2 ? try Self.parseGroups(in: halves[1], of: text) : []

        if halves.count == 2 {
            // :: steht für mindestens einen Nullblock. Sind schon acht Blöcke
            // ausgeschrieben, ist die Adresse falsch und nicht etwa lang.
            guard head.count + tail.count <= 7 else { throw Self.notAnAddress(text) }
            let filler = Array(repeating: UInt16(0), count: 8 - head.count - tail.count)
            self.init(groups: head + filler + tail)
        } else {
            guard head.count == 8 else { throw Self.notAnAddress(text) }
            self.init(groups: head)
        }
    }

    /// Liest eine Hälfte: Blöcke aus Hexziffern, am Ende erlaubt eine
    /// eingebettete IPv4-Adresse.
    private static func parseGroups(in part: String, of text: String) throws -> [UInt16] {
        guard !part.isEmpty else { return [] }

        var result: [UInt16] = []
        let pieces = part.components(separatedBy: ":")
        for (index, piece) in pieces.enumerated() {
            if piece.contains(".") {
                // ::ffff:192.168.1.1 — die vier Bytes füllen die letzten zwei
                // Blöcke und dürfen deshalb nur ganz am Ende stehen.
                guard index == pieces.count - 1 else { throw notAnAddress(text) }
                let embedded = try IPv4Address(parsing: piece)
                result.append(UInt16(truncatingIfNeeded: embedded.value >> 16))
                result.append(UInt16(truncatingIfNeeded: embedded.value))
                continue
            }
            guard !piece.isEmpty,
                  piece.count <= 4,
                  piece.allSatisfy({ $0.isASCII && $0.isHexDigit }),
                  let group = UInt16(piece, radix: 16)
            else { throw notAnAddress(text) }
            result.append(group)
        }
        return result
    }

    public var groups: [UInt16] {
        (0..<8).map { index in
            let source = index < 4 ? high : low
            let shift = (3 - (index % 4)) * 16
            return UInt16(truncatingIfNeeded: source >> UInt64(shift))
        }
    }

    /// Ausgeschrieben: acht Blöcke zu vier Stellen, nichts weggelassen.
    public var expandedText: String {
        groups.map { String(format: "%04x", $0) }.joined(separator: ":")
    }

    /// Gekürzt nach RFC 5952.
    ///
    /// Drei Regeln, und alle drei werden regelmäßig falsch gemacht: führende
    /// Nullen fallen weg; nur die **längste** Folge von Nullblöcken wird zu
    /// `::`, denn zwei `::` ließen sich nicht mehr auflösen; und eine Folge aus
    /// einem einzigen Nullblock bleibt stehen, weil `::` dort nichts kürzt.
    public var compressedText: String {
        let groups = self.groups
        var bestStart = -1
        var bestLength = 0
        var index = 0
        while index < groups.count {
            guard groups[index] == 0 else {
                index += 1
                continue
            }
            var end = index
            while end < groups.count, groups[end] == 0 { end += 1 }
            // Echt größer: bei Gleichstand gewinnt die erste Folge.
            if end - index > bestLength {
                bestLength = end - index
                bestStart = index
            }
            index = end
        }

        func written(_ slice: ArraySlice<UInt16>) -> String {
            slice.map { String($0, radix: 16) }.joined(separator: ":")
        }

        guard bestLength >= 2 else { return written(groups[...]) }
        return written(groups[0..<bestStart]) + "::" + written(groups[(bestStart + bestLength)...])
    }

    public var description: String { compressedText }

    // MARK: Bitarbeit

    public func masked(by mask: IPv6Address) -> IPv6Address {
        IPv6Address(high: high & mask.high, low: low & mask.low)
    }

    public var inverted: IPv6Address {
        IPv6Address(high: ~high, low: ~low)
    }

    public func union(_ other: IPv6Address) -> IPv6Address {
        IPv6Address(high: high | other.high, low: low | other.low)
    }

    /// Addiert `index * 2^shift` — der Schritt von einem Teilnetz zum nächsten.
    func adding(_ index: UInt64, shiftedBy shift: Int) -> IPv6Address {
        let offsetHigh: UInt64
        let offsetLow: UInt64
        if shift >= 64 {
            offsetHigh = index << (shift - 64)
            offsetLow = 0
        } else {
            offsetHigh = index >> (64 - shift)
            offsetLow = index << shift
        }
        let (shiftedLow, carry) = low.addingReportingOverflow(offsetLow)
        return IPv6Address(high: high &+ offsetHigh &+ (carry ? 1 : 0), low: shiftedLow)
    }

    static func notAnAddress(_ text: String) -> AnvilError {
        AnvilError.invalidInput(localized("Das ist keine IPv6-Adresse: \(text)"))
    }
}

/// Ein IPv6-Netz.
public struct IPv6Network: Hashable, Sendable, CustomStringConvertible {
    public let address: IPv6Address
    public let prefixLength: Int

    init(_ address: IPv6Address, prefixLength: Int) {
        self.address = address
        self.prefixLength = prefixLength
    }

    public init(address: IPv6Address, prefixLength: Int) throws {
        guard (0...128).contains(prefixLength) else {
            throw AnvilError.invalidInput(
                localized("Eine IPv6-Präfixlänge liegt zwischen 0 und 128.")
            )
        }
        self.init(address, prefixLength: prefixLength)
    }

    public init(parsing text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AnvilError.invalidInput(localized("Da steht noch keine Adresse."))
        }

        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let addressPart = parts.first, parts.count <= 2 else {
            throw AnvilError.invalidInput(
                localized("Ein Netz besteht aus einer Adresse und höchstens einer Angabe dahinter: \(text)")
            )
        }

        let address = try IPv6Address(parsing: addressPart)
        guard parts.count == 2 else {
            // IPv6 kennt keine Masken in Punktschreibweise; ohne Angabe ist
            // genau diese eine Adresse gemeint.
            try self.init(address: address, prefixLength: 128)
            return
        }
        guard let prefixLength = Int(parts[1]) else {
            throw AnvilError.invalidInput(
                localized("Hinter dem Schrägstrich steht eine Präfixlänge: \(parts[1])")
            )
        }
        try self.init(address: address, prefixLength: prefixLength)
    }

    public var mask: IPv6Address {
        IPv6Address(
            high: prefixLength >= 64 ? UInt64.max : UInt64.max << (64 - prefixLength),
            low: prefixLength <= 64 ? 0 : UInt64.max << (128 - prefixLength)
        )
    }

    public var networkAddress: IPv6Address { address.masked(by: mask) }

    public var lastAddress: IPv6Address { networkAddress.union(mask.inverted) }

    /// Als Dezimaltext, weil ein /0 mehr Adressen hat, als jede Ganzzahl
    /// dieses Rechners fasst.
    public var addressCountText: String { IPMath.powerOfTwo(128 - prefixLength) }

    public var scope: IPScope { IPScope.of(networkAddress) }

    public func contains(_ candidate: IPv6Address) -> Bool {
        candidate.masked(by: mask) == networkAddress
    }

    public var description: String { "\(networkAddress.compressedText)/\(prefixLength)" }

    /// IPv6 kennt keinen Broadcast und keine für das Netz reservierte erste
    /// Adresse — jede Adresse im Präfix ist benutzbar.
    public var note: String? {
        guard prefixLength == 128 else { return nil }
        return localized("Genau eine Adresse — ein einzelner Host, kein Netz mit Hostbereich.")
    }

    // MARK: Teilen

    private func validateSplit(_ newPrefixLength: Int) throws {
        guard (0...128).contains(newPrefixLength) else {
            throw AnvilError.invalidInput(
                localized("Eine IPv6-Präfixlänge liegt zwischen 0 und 128.")
            )
        }
        guard newPrefixLength >= prefixLength else {
            throw AnvilError.invalidInput(
                localized("Ein Teilnetz kann nicht größer sein als das Netz, aus dem es kommt.")
            )
        }
    }

    public func subnetCountText(splittingInto newPrefixLength: Int) throws -> String {
        try validateSplit(newPrefixLength)
        return IPMath.powerOfTwo(newPrefixLength - prefixLength)
    }

    public func split(into newPrefixLength: Int, limit: Int = 64) throws -> [IPv6Network] {
        try validateSplit(newPrefixLength)
        let exponent = newPrefixLength - prefixLength
        // 2^64 passt nicht mehr in einen UInt64. Ab dort ist die Liste ohnehin
        // längst gekappt, also reicht „mehr als jedes Limit".
        let total: UInt64 = exponent >= 64 ? UInt64.max : (UInt64(1) << exponent)
        let shown = min(total, UInt64(max(limit, 0)))
        let base = networkAddress
        let shift = 128 - newPrefixLength
        return (0..<shown).map { index in
            IPv6Network(base.adding(index, shiftedBy: shift), prefixLength: newPrefixLength)
        }
    }
}

// MARK: - Einordnung

/// Wofür ein Adressbereich vorgesehen ist.
///
/// Der praktische Nutzen: wer eine Adresse in einem Log sieht, will in einer
/// Sekunde wissen, ob sie überhaupt aus dem Internet kommen kann.
public enum IPScope: String, Hashable, Sendable, CaseIterable {
    case unspecified
    case loopback
    case privateUse
    case sharedAddressSpace
    case linkLocal
    case uniqueLocal
    case multicast
    case documentation
    case benchmarking
    case reserved
    case broadcast
    case ipv4Mapped
    case global

    public var title: String {
        switch self {
        case .unspecified: localized("Nicht festgelegt")
        case .loopback: localized("Nur dieser Rechner")
        case .privateUse: localized("Privates Netz (RFC 1918)")
        case .sharedAddressSpace: localized("Anbieter-NAT (RFC 6598)")
        case .linkLocal: localized("Nur dieses Netzsegment")
        case .uniqueLocal: localized("Eindeutig lokal (RFC 4193)")
        case .multicast: localized("Multicast")
        case .documentation: localized("Für Beispiele reserviert")
        case .benchmarking: localized("Für Messungen reserviert")
        case .reserved: localized("Reserviert")
        case .broadcast: localized("Broadcast an alle")
        case .ipv4Mapped: localized("IPv4 in IPv6 abgebildet")
        case .global: localized("Öffentlich erreichbar")
        }
    }

    public var systemImage: String {
        switch self {
        case .unspecified: "circle.dotted"
        case .loopback: "arrow.uturn.backward"
        case .privateUse: "house"
        case .sharedAddressSpace: "person.2"
        case .linkLocal: "cable.connector"
        case .uniqueLocal: "lock.shield"
        case .multicast: "dot.radiowaves.left.and.right"
        case .documentation: "book"
        case .benchmarking: "speedometer"
        case .reserved: "exclamationmark.triangle"
        case .broadcast: "antenna.radiowaves.left.and.right"
        case .ipv4Mapped: "arrow.left.arrow.right"
        case .global: "globe"
        }
    }

    /// Öffentliche Adressen sind der Normalfall und bekommen deshalb keine
    /// Warnfarbe — auffallen soll, was nicht routbar ist.
    public var tone: AnvilScopeTone {
        switch self {
        case .global: .info
        case .privateUse, .uniqueLocal, .sharedAddressSpace: .accent
        case .loopback, .linkLocal, .ipv4Mapped, .multicast: .neutral
        case .unspecified, .documentation, .benchmarking, .reserved, .broadcast: .warning
        }
    }

    // MARK: IPv4

    /// Die Bereiche, die IANA aus dem allgemeinen Verkehr herausgenommen hat.
    ///
    /// Die Reihenfolge trägt Bedeutung: 255.255.255.255 liegt in 240.0.0.0/4,
    /// ist aber nicht einfach „reserviert", also muss der engere Eintrag
    /// zuerst geprüft werden.
    static let v4Ranges: [(base: UInt32, prefixLength: Int, scope: IPScope)] = [
        (0xFFFF_FFFF, 32, .broadcast),          // 255.255.255.255
        (0x0000_0000, 8, .unspecified),         // 0.0.0.0/8
        (0x7F00_0000, 8, .loopback),            // 127.0.0.0/8
        (0x0A00_0000, 8, .privateUse),          // 10.0.0.0/8
        (0xAC10_0000, 12, .privateUse),         // 172.16.0.0/12
        (0xC0A8_0000, 16, .privateUse),         // 192.168.0.0/16
        (0x6440_0000, 10, .sharedAddressSpace), // 100.64.0.0/10
        (0xA9FE_0000, 16, .linkLocal),          // 169.254.0.0/16
        (0xC000_0200, 24, .documentation),      // 192.0.2.0/24
        (0xC633_6400, 24, .documentation),      // 198.51.100.0/24
        (0xCB00_7100, 24, .documentation),      // 203.0.113.0/24
        (0xC612_0000, 15, .benchmarking),       // 198.18.0.0/15
        (0xE000_0000, 4, .multicast),           // 224.0.0.0/4
        (0xF000_0000, 4, .reserved)             // 240.0.0.0/4
    ]

    public static func of(_ address: IPv4Address) -> IPScope {
        for range in v4Ranges {
            let mask = UInt32.max << (32 - range.prefixLength)
            if address.value & mask == range.base { return range.scope }
        }
        return .global
    }

    // MARK: IPv6

    public static func of(_ address: IPv6Address) -> IPScope {
        if address.high == 0 {
            if address.low == 0 { return .unspecified }
            if address.low == 1 { return .loopback }
            // ::ffff:0:0/96
            if address.low >> 32 == 0xFFFF { return .ipv4Mapped }
        }
        // ff00::/8
        if address.high >> 56 == 0xFF { return .multicast }
        // fe80::/10
        if address.high >> 54 == 0x3FA { return .linkLocal }
        // fc00::/7
        if address.high >> 57 == 0x7E { return .uniqueLocal }
        // 2001:db8::/32
        if address.high >> 32 == 0x2001_0DB8 { return .documentation }
        return .global
    }
}

/// Welche Farbe eine Einordnung in der Oberfläche bekommt.
///
/// Ein eigener Typ, damit ``IPScope`` — und damit die ganze Rechnerei — ohne
/// das Design-System auskommt und in einem Test ohne Fenster läuft.
public enum AnvilScopeTone: String, Hashable, Sendable {
    case neutral
    case accent
    case info
    case warning
}

// MARK: - Beides zusammen

/// Ein Netz, egal welcher Familie.
///
/// Die Oberfläche hat ein Eingabefeld, nicht zwei — welche Familie gemeint ist,
/// steht in der Eingabe selbst.
public enum IPNetwork: Hashable, Sendable, CustomStringConvertible {
    case v4(IPv4Network)
    case v6(IPv6Network)

    public init(parsing text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AnvilError.invalidInput(localized("Da steht noch keine Adresse."))
        }
        // Ein Doppelpunkt kommt in einer IPv4-Schreibweise nirgends vor, also
        // reicht er zur Unterscheidung — auch bei ::ffff:192.168.1.1.
        if trimmed.contains(":") {
            self = .v6(try IPv6Network(parsing: trimmed))
        } else {
            self = .v4(try IPv4Network(parsing: trimmed))
        }
    }

    public var family: IPFamily {
        switch self {
        case .v4: .v4
        case .v6: .v6
        }
    }

    public var prefixLength: Int {
        switch self {
        case let .v4(network): network.prefixLength
        case let .v6(network): network.prefixLength
        }
    }

    public var scope: IPScope {
        switch self {
        case let .v4(network): network.scope
        case let .v6(network): network.scope
        }
    }

    public var addressCountText: String {
        switch self {
        case let .v4(network): "\(network.addressCount)"
        case let .v6(network): network.addressCountText
        }
    }

    /// Nur IPv4 unterscheidet zwischen Adressen und benutzbaren Hosts.
    public var usableHostCountText: String? {
        switch self {
        case let .v4(network): "\(network.usableHostCount)"
        case .v6: nil
        }
    }

    public var note: String? {
        switch self {
        case let .v4(network): network.note
        case let .v6(network): network.note
        }
    }

    public var description: String {
        switch self {
        case let .v4(network): network.description
        case let .v6(network): network.description
        }
    }

    /// Erste und letzte Adresse, als eine Zeile.
    public var rangeText: String {
        switch self {
        case let .v4(network): "\(network.networkAddress.text) – \(network.lastAddress.text)"
        case let .v6(network): "\(network.networkAddress.compressedText) – \(network.lastAddress.compressedText)"
        }
    }

    // MARK: Enthalten?

    /// Was beim Prüfen einer Adresse herauskommt.
    public enum Containment: String, Hashable, Sendable {
        case inside
        case outside
        /// Eine IPv6-Adresse in einem IPv4-Netz zu suchen ist keine Frage, auf
        /// die „nein" die ehrliche Antwort wäre.
        case differentFamily
        case unreadable

        public var title: String {
            switch self {
            case .inside: localized("Liegt im Netz")
            case .outside: localized("Liegt außerhalb")
            case .differentFamily: localized("Andere Familie")
            case .unreadable: localized("Keine Adresse")
            }
        }

        public var systemImage: String {
            switch self {
            case .inside: "checkmark.circle"
            case .outside: "xmark.circle"
            case .differentFamily: "arrow.triangle.branch"
            case .unreadable: "questionmark.circle"
            }
        }

        public var tone: AnvilScopeTone {
            switch self {
            case .inside: .accent
            case .outside: .neutral
            case .differentFamily, .unreadable: .warning
            }
        }
    }

    public func containment(of text: String) -> Containment {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unreadable }

        switch self {
        case let .v4(network):
            guard !trimmed.contains(":") else { return .differentFamily }
            guard let candidate = try? IPv4Address(parsing: trimmed) else { return .unreadable }
            return network.contains(candidate) ? .inside : .outside
        case let .v6(network):
            guard trimmed.contains(":") else { return .differentFamily }
            guard let candidate = try? IPv6Address(parsing: trimmed) else { return .unreadable }
            return network.contains(candidate) ? .inside : .outside
        }
    }

    // MARK: Teilen

    /// Ein Netz, zerlegt in gleich große Teile.
    public struct Split: Sendable {
        /// Wie viele es insgesamt sind — als Text, weil es bei IPv6 mehr sein
        /// können, als in eine Ganzzahl passt.
        public let countText: String
        /// Die ersten davon.
        public let subnets: [IPNetwork]
        /// Ob die Liste gekappt wurde.
        public let isTruncated: Bool
    }

    public func split(into newPrefixLength: Int, limit: Int = 64) throws -> Split {
        switch self {
        case let .v4(network):
            let count = try network.subnetCount(splittingInto: newPrefixLength)
            let subnets = try network.split(into: newPrefixLength, limit: limit)
            return Split(
                countText: "\(count)",
                subnets: subnets.map(IPNetwork.v4),
                isTruncated: UInt64(subnets.count) < count
            )
        case let .v6(network):
            let countText = try network.subnetCountText(splittingInto: newPrefixLength)
            let subnets = try network.split(into: newPrefixLength, limit: limit)
            // Der Vergleich läuft über den Text: die echte Zahl passt bei IPv6
            // nicht zuverlässig in einen `UInt64`.
            return Split(
                countText: countText,
                subnets: subnets.map(IPNetwork.v6),
                isTruncated: countText != "\(subnets.count)"
            )
        }
    }
}
