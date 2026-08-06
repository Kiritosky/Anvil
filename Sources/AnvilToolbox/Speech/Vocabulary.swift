import AnvilKit
import Foundation
import Observation

/// One term the speech recogniser keeps getting wrong.
///
/// Recognition is trained on ordinary language, so the words it mangles are
/// exactly the ones you care about most: product names, colleagues, API
/// identifiers. A short personal list fixes more of a dictation than any amount
/// of prompt tuning.
public struct VocabularyEntry: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    /// The correct spelling — what should end up in the text.
    public var term: String
    /// Misrecognitions to replace outright, when you already know them.
    ///
    /// Fuzzy matching catches "Anwil" for "Anvil" on its own; variants are for
    /// the cases it cannot, where the recogniser produces something that only
    /// *sounds* similar: "Tool Registrierung" for "ToolRegistration".
    public var variants: [String]
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        term: String,
        variants: [String] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.term = term
        self.variants = variants
        self.isEnabled = isEnabled
    }

    /// How many words the term consists of. Drives the window size when
    /// scanning a transcript.
    public var wordCount: Int {
        max(1, term.split(whereSeparator: \.isWhitespace).count)
    }
}

/// The user's word list.
@MainActor
@Observable
public final class VocabularyStore {
    @ObservationIgnored private let settings: SettingsStore

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    public var entries: [VocabularyEntry] {
        get { settings[.vocabulary] }
        set { settings[.vocabulary] = newValue }
    }

    public var activeEntries: [VocabularyEntry] {
        entries.filter { $0.isEnabled && !$0.term.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public var isEmpty: Bool { activeEntries.isEmpty }

    public func add(_ entry: VocabularyEntry) {
        entries.append(entry)
    }

    public func update(_ entry: VocabularyEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
    }

    public func remove(_ entry: VocabularyEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    public func toggle(_ entry: VocabularyEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isEnabled.toggle()
    }

    /// A corrector over the currently active entries.
    public func corrector(sensitivity: VocabularyCorrector.Sensitivity? = nil) -> VocabularyCorrector {
        VocabularyCorrector(
            entries: activeEntries,
            sensitivity: sensitivity ?? settings[.vocabularySensitivity]
        )
    }

    /// The terms handed to the model, capped so a long list cannot eat the
    /// on-device context window.
    public func promptTerms(limit: Int = 60) -> [String] {
        Array(activeEntries.map(\.term).prefix(limit))
    }
}

extension SettingKey {
    public static var vocabulary: SettingKey<[VocabularyEntry]> {
        SettingKey<[VocabularyEntry]>("speech.vocabulary", default: [])
    }

    public static var vocabularySensitivity: SettingKey<VocabularyCorrector.Sensitivity> {
        SettingKey<VocabularyCorrector.Sensitivity>("speech.vocabularySensitivity", default: .balanced)
    }

    /// Also hand the terms to the model, not just the deterministic pass.
    public static var vocabularyInPrompt: SettingKey<Bool> {
        SettingKey<Bool>("speech.vocabularyInPrompt", default: true)
    }
}

// MARK: - Tool context

extension ToolContext {
    /// The word list, registered by the app at launch.
    public var vocabulary: VocabularyStore { require(VocabularyStore.self) }
}
