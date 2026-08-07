import Foundation

/// Was in einem Werkzeug stand, als man es zuletzt verlassen hat.
///
/// Eine Werkzeugkiste, zu der man zurückkommt, sollte nicht jedes Mal leer
/// sein. Gespeichert wird deshalb die letzte Eingabe — aber nur die, und nur
/// wenn drei Bedingungen stimmen:
///
/// 1. Das Werkzeug hat mit Geheimnissen nichts zu tun (``allows(_:)``).
/// 2. Der Text sieht nicht nach einem Geheimnis aus (``Sensitivity``).
/// 3. Er ist klein genug, dass eine JSON-Datei dafür angemessen ist.
///
/// Ergebnisse werden nie gespeichert. Sie entstehen aus der Eingabe in
/// Millisekunden neu, und ein Ergebnis kann verräterischer sein als die
/// Eingabe — der entzifferte Inhalt eines Tokens etwa.
@MainActor
public final class DraftStore {
    /// Ab hier ist es kein „ich mache gleich weiter" mehr, sondern ein
    /// Datensatz. 64 KB reichen für jeden Text, den jemand von Hand einfügt.
    public static let sizeLimit = 64 * 1024

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private var cache: [ToolIdentifier: Draft] = [:]

    public init(directory: URL = AppPaths.drafts) {
        self.directory = directory
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    /// Der gemerkte Stand eines Werkzeugs.
    public struct Draft: Codable, Equatable, Sendable {
        public var input: String
        /// Welche Variante zuletzt gewählt war — „SHA-256", „Formatieren".
        public var modeID: String?
        public var savedAt: Date

        public init(input: String, modeID: String? = nil, savedAt: Date = .now) {
            self.input = input
            self.modeID = modeID
            self.savedAt = savedAt
        }
    }

    // MARK: - Lesen und schreiben

    public func draft(for tool: ToolIdentifier) -> Draft? {
        if let cached = cache[tool] { return cached }
        guard let data = try? Data(contentsOf: url(for: tool)),
              let draft = try? decoder.decode(Draft.self, from: data)
        else { return nil }
        cache[tool] = draft
        return draft
    }

    /// Merkt sich den Stand — oder löscht ihn, wenn er nicht gespeichert
    /// werden darf.
    ///
    /// Das Löschen ist der wichtige Teil: wer einen Schlüssel in ein Feld
    /// einfügt, in dem vorher etwas Harmloses stand, soll nicht das Harmlose
    /// auf der Platte behalten und den Schlüssel im Fenster. Beides muss weg.
    public func save(_ draft: Draft, for tool: ToolIdentifier, allowed: Bool = true) {
        guard allowed, Self.mayStore(draft.input) else {
            forget(tool)
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try encoder.encode(draft).write(to: url(for: tool))
            cache[tool] = draft
        } catch {
            // Ein Entwurf ist Bequemlichkeit, kein Auftrag. Scheitert das
            // Schreiben, ist das kein Grund, dem Benutzer etwas zu melden.
            cache[tool] = draft
        }
    }

    public func forget(_ tool: ToolIdentifier) {
        cache[tool] = nil
        try? FileManager.default.removeItem(at: url(for: tool))
    }

    /// Wirft alles weg. Hängt in den Einstellungen an einem Knopf, und wird
    /// gebraucht, wenn jemand das Merken abschaltet: sonst bliebe liegen, was
    /// bis dahin gemerkt wurde.
    public func forgetEverything() {
        cache = [:]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    // MARK: - Die Entscheidung

    /// Ob dieser Text überhaupt gespeichert werden darf.
    ///
    /// Nicht `private`, weil genau hier die Regel steckt, die stimmen muss —
    /// und eine Regel, die man nicht prüfen kann, ist eine Hoffnung.
    public static func mayStore(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard text.utf8.count <= sizeLimit else { return false }
        return !Sensitivity.looksConfidential(text)
    }

    private func url(for tool: ToolIdentifier) -> URL {
        // Werkzeug-Kennungen sind Punkt-getrennte Bezeichner ohne
        // Pfadtrenner, taugen also unverändert als Dateiname.
        directory.appending(path: "\(tool.rawValue).json")
    }
}

extension ToolContext {
    /// Die gemerkten Eingaben, von der App beim Start registriert.
    public var drafts: DraftStore { require(DraftStore.self) }
}

extension SettingKey {
    /// Ob Werkzeuge sich merken, was zuletzt drinstand.
    ///
    /// An, weil eine Werkzeugkiste, die jedes Mal leer ist, lästig ist — und
    /// weil das, was hier landen darf, ohnehin nichts Vertrauliches ist.
    public static var remembersInput: SettingKey<Bool> {
        SettingKey<Bool>("tools.remembersInput", default: true)
    }
}
