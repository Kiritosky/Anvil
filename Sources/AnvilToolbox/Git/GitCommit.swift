import AnvilKit
import Foundation

/// Der letzte Commit eines Repositories.
///
/// Die Übersicht sagt bisher, ob etwas offen ist. Die zweite Frage, die man
/// beim Durchsehen von dreißig Ordnern hat, ist eine andere: Wann habe ich das
/// hier zuletzt angefasst? Ein Repository, in dem seit zwei Jahren nichts
/// passiert ist, will man nicht aufräumen — man will wissen, dass es das gibt.
public struct GitCommit: Sendable, Hashable {
    /// Die kurze Prüfsumme, so wie `git` sie selbst abkürzt.
    public let hash: String
    public let date: Date?
    public let author: String
    /// Die erste Zeile der Commit-Nachricht.
    public let subject: String

    public init(hash: String, date: Date?, author: String, subject: String) {
        self.hash = hash
        self.date = date
        self.author = author
        self.subject = subject
    }

    /// Das Format für `git log -1`.
    ///
    /// Tabulatorgetrennt (`%x09`), weil in einer Commit-Nachricht alles
    /// vorkommt — Doppelpunkte, Bindestriche, Anführungszeichen — nur kein
    /// Tabulator, den `git` in der ersten Zeile ohnehin nicht durchlässt.
    public static let logFormat = "%h%x09%cI%x09%an%x09%s"

    /// Zerlegt eine Zeile im Format von ``logFormat``.
    public static func read(_ text: String) -> GitCommit? {
        guard let line = TextLines.split(text, keepingEmpty: false).first else { return nil }
        let fields = line.components(separatedBy: "\t")
        guard fields.count >= 4, !fields[0].isEmpty else { return nil }

        return GitCommit(
            hash: fields[0],
            date: isoFormatter.date(from: fields[1]),
            author: fields[2],
            // Ein Tabulator in der Nachricht würde hier landen; wieder
            // zusammengesetzt steht sie so da, wie sie geschrieben wurde.
            subject: fields[3...].joined(separator: "\t")
        )
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Wie viele Tage seither vergangen sind.
    public func age(now: Date = Date()) -> Int? {
        guard let date else { return nil }
        return Calendar.current.dateComponents([.day], from: date, to: now).day
    }

    /// „vor 3 Tagen", „heute" — was in einer Tabellenspalte Platz hat.
    public func ageText(now: Date = Date()) -> String {
        guard let days = age(now: now) else { return "—" }
        if days <= 0 { return localized("heute") }
        if days == 1 { return localized("gestern") }
        return localized("vor \(days) Tagen")
    }
}
