import AnvilKit
import Foundation

/// Mehrere Netze auf einmal — eins je Zeile.
///
/// Ein Rechner für genau ein Netz ist ein Taschenrechner. Interessant wird die
/// Sache erst, wenn eine ganze Liste danebenliegt: die Netze aus einer
/// Firewall-Regel, aus einem Ticket, aus einer Tabelle. Deshalb ist die
/// Mehrzahl hier der Normalfall und das eine Netz nur ihr kürzester Fall.
public struct NetworkList: Sendable {
    /// Eine Zeile der Eingabe, gelesen oder eben nicht.
    ///
    /// Unlesbare Zeilen fallen nicht heraus. Wer zwanzig Netze einwirft und
    /// achtzehn Ergebnisse bekommt, sucht sonst die fehlenden zwei von Hand.
    public struct Entry: Sendable, Identifiable {
        /// Die Zeilennummer der Eingabe, ab 1 — auch die Kennung in der Liste.
        public let id: Int
        /// Die Zeile, wie sie dastand.
        public let text: String
        public let network: IPNetwork?
        /// Warum die Zeile nicht zu lesen war.
        public let message: String?

        public var isReadable: Bool { network != nil }
    }

    public let entries: [Entry]

    /// Leere Zeilen und Kommentarzeilen fallen weg.
    ///
    /// `#` und `;` deshalb, weil eine Liste von Netzen fast immer aus einer
    /// Konfigurationsdatei kommt und dort beides als Kommentar gilt.
    public init(parsing text: String) {
        var entries: [Entry] = []
        for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }
            do {
                let network = try IPNetwork(parsing: line)
                entries.append(Entry(id: offset + 1, text: line, network: network, message: nil))
            } catch {
                entries.append(
                    Entry(id: offset + 1, text: line, network: nil, message: error.localizedDescription)
                )
            }
        }
        self.entries = entries
    }

    public var networks: [IPNetwork] { entries.compactMap(\.network) }

    public var readableCount: Int { entries.lazy.filter(\.isReadable).count }

    public var unreadableCount: Int { entries.count - readableCount }

    public var isEmpty: Bool { entries.isEmpty }

    /// Das eine Netz, wenn es genau eines ist.
    ///
    /// Die Oberfläche zeigt dann alles darüber; ab zwei wird aus der Ansicht
    /// eine Liste, weil zwanzig ausführliche Steckbriefe niemand liest.
    public var single: IPNetwork? {
        entries.count == 1 ? entries[0].network : nil
    }

    /// Alle Netze in Normalform, eins je Zeile.
    ///
    /// Genau das, was man zurück in die Konfiguration schreibt: Hostbits weg,
    /// IPv6 gekürzt, Maske als Präfixlänge.
    public var normalizedText: String {
        networks.map(\.description).joined(separator: "\n")
    }

    /// Die ganze Liste als Tabelle.
    ///
    /// Tabulatorgetrennt, weil das Ergebnis fast immer in einer Tabelle oder in
    /// einem Ticket landet. Ausgerichtete Spalten sähen hier besser aus und
    /// wären beim Einfügen wertlos.
    public var report: String {
        let header = [
            localized("Netz"),
            localized("Bereich"),
            localized("Maske"),
            localized("Adressen"),
            localized("Hosts"),
            localized("Einordnung")
        ].joined(separator: "\t")

        let rows = entries.map { entry -> String in
            guard let network = entry.network else {
                return [entry.text, entry.message ?? localized("Nicht lesbar")].joined(separator: "\t")
            }
            return [
                network.description,
                network.rangeText,
                network.maskText ?? "—",
                network.addressCountText,
                network.usableHostCountText ?? "—",
                network.scope.title
            ].joined(separator: "\t")
        }

        return ([header] + rows).joined(separator: "\n")
    }

    /// Die Zeilen, in denen die gesuchte Adresse liegt.
    ///
    /// Die eigentliche Frage an eine Liste von Netzen: *In welches davon fällt
    /// diese eine Adresse?* — meistens gestellt vor einer Firewall-Regel.
    public func entries(containing text: String) -> [Entry] {
        entries.filter { $0.network?.containment(of: text) == .inside }
    }
}

extension IPNetwork {
    /// Die Maske in Punktschreibweise — IPv6 hat keine.
    public var maskText: String? {
        switch self {
        case let .v4(network): network.mask.text
        case .v6: nil
        }
    }

    /// Die Zeilen, die ein einzelnes Netz beschreiben.
    ///
    /// Steht hier und nicht in der View, damit der Steckbrief und das, was der
    /// Kopieren-Knopf herausgibt, nicht auseinanderlaufen können.
    public var details: [(key: String, value: String)] {
        var rows: [(key: String, value: String)] = [
            (localized("Netz"), description),
            (localized("Bereich"), rangeText)
        ]

        switch self {
        case let .v4(network):
            rows.append((localized("Maske"), network.mask.text))
            rows.append((localized("Wildcard"), network.wildcard.text))
            if let first = network.firstUsableAddress, let last = network.lastUsableAddress {
                rows.append((localized("Hostbereich"), "\(first.text) – \(last.text)"))
            }
            if let broadcast = network.broadcastAddress {
                rows.append((localized("Broadcast"), broadcast.text))
            }
        case let .v6(network):
            rows.append((localized("Ausgeschrieben"), network.networkAddress.expandedText))
            rows.append((localized("Letzte Adresse"), network.lastAddress.expandedText))
        }

        rows.append((localized("Adressen"), IPMath.grouped(addressCountText)))
        if let hosts = usableHostCountText {
            rows.append((localized("Benutzbare Hosts"), IPMath.grouped(hosts)))
        }
        rows.append((localized("Präfixlänge"), "/\(prefixLength)"))
        rows.append((localized("Einordnung"), scope.title))
        return rows
    }
}
