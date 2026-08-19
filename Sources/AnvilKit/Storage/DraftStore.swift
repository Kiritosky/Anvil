import Foundation

/// Was in einem Werkzeug stand, als man es zuletzt verlassen hat.
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
        /// Weitere Felder für Werkzeuge mit mehr als einer Eingabe: das
        /// Muster beim Regex-Tester, die zweite Fassung beim Textvergleich.
        public var extras: [String: String]
        public var savedAt: Date

        public init(
            input: String,
            modeID: String? = nil,
            extras: [String: String] = [:],
            savedAt: Date = .now
        ) {
            self.input = input
            self.modeID = modeID
            self.extras = extras
            self.savedAt = savedAt
        }

        public func extra(_ name: String) -> String {
            extras[name] ?? ""
        }

        /// Jeder Text, der bei diesem Entwurf auf der Platte landen würde.
        var allText: [String] {
            [input] + extras.values
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
    public func save(_ draft: Draft, for tool: ToolIdentifier, allowed: Bool = true) {
        guard allowed, draft.allText.contains(where: { !$0.isEmpty }),
              draft.allText.allSatisfy({ $0.isEmpty || Self.mayStore($0) })
        else {
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
    public static func mayStore(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard text.utf8.count <= sizeLimit else { return false }
        return !Sensitivity.looksConfidential(text)
    }

    private func url(for tool: ToolIdentifier) -> URL {
        directory.appending(path: "\(tool.rawValue).json")
    }
}

extension ToolContext {
    /// Die gemerkten Eingaben, von der App beim Start registriert.
    public var drafts: DraftStore { require(DraftStore.self) }
}

extension SettingKey {
    /// Ob Werkzeuge sich merken, was zuletzt drinstand.
    public static var remembersInput: SettingKey<Bool> {
        SettingKey<Bool>("tools.remembersInput", default: true)
    }
}
