import AnvilKit
import Foundation

/// Ein eigenes Werkzeug, bevor es eines ist.
///
/// Anvil kann seit jeher eigene Prompt-Werkzeuge laden — als JSON-Datei in
/// einem Ordner, ohne Neubauen. Nur: Diesen Ordner findet man nur, wenn man
/// weiß, dass es ihn gibt, und die Datei schreibt sich nur, wenn man das
/// Schema kennt. Damit war „erweiterbar von Anfang an" ein Versprechen an
/// Leute, die ohnehin JSON schreiben.
///
/// Dieser Entwurf ist die Zwischenstufe: Was jemand in ein Formular tippt,
/// bis daraus ein `AIPromptTool` wird. Er sagt vorher, was noch fehlt — und
/// zwar bevor eine Datei entsteht, die beim Laden scheitert.
public struct CustomToolDraft: Sendable, Hashable {
    public var title = ""
    public var subtitle = ""
    public var systemImage = "wand.and.stars"
    public var keywords = ""
    /// Die Anweisung an das Modell — das eigentliche Werkzeug.
    public var instructions = ""
    public var inputPlaceholder = ""
    public var temperature = 0.4

    /// Eine einzige Wahlmöglichkeit, weil eine reicht, um den Bogen zu
    /// spannen: Wer mehr braucht, hat die Datei und weiß dann auch, wie sie
    /// aussieht.
    public var optionLabel = ""
    /// Die Auswahl, mit Komma getrennt.
    public var optionChoices = ""

    public init() {}

    // MARK: - Was fehlt

    public enum Problem: String, Sendable, Hashable, CaseIterable {
        case titleMissing
        case instructionsMissing
        case identifierTaken
        case optionWithoutChoices
        case optionNotUsed

        public var title: String {
            switch self {
            case .titleMissing: localized("Ein Titel fehlt")
            case .instructionsMissing: localized("Die Anweisung fehlt")
            case .identifierTaken: localized("Ein Werkzeug mit diesem Namen gibt es schon")
            case .optionWithoutChoices: localized("Die Wahl hat keine Möglichkeiten")
            case .optionNotUsed: localized("Die Wahl kommt in der Anweisung nicht vor")
            }
        }

        /// Ob es das Sichern verhindert.
        ///
        /// Eine Wahl, die nirgends eingesetzt wird, ist ein Hinweis und kein
        /// Fehler: Vielleicht kommt der Platzhalter im nächsten Satz.
        public var isBlocking: Bool { self != .optionNotUsed }
    }

    /// Die Kennung, unter der das Werkzeug läuft.
    ///
    /// Aus dem Titel gebildet und mit `user.` davor, damit sie sich nie mit
    /// einem eingebauten Werkzeug beißt.
    public var identifier: String {
        let slug = Slug.make(title)
        return slug.isEmpty ? "user.werkzeug" : "user.\(slug)"
    }

    public var fileName: String {
        let slug = Slug.make(title)
        return (slug.isEmpty ? "werkzeug" : slug) + ".json"
    }

    /// Die Kennung der Wahlmöglichkeit — sie steht so im Platzhalter.
    public var optionID: String {
        let slug = Slug.make(optionLabel, separator: "")
        return slug.isEmpty ? "wahl" : slug
    }

    /// Der Platzhalter, der in der Anweisung stehen muss, damit die Wahl
    /// überhaupt etwas tut.
    public var optionPlaceholder: String { "{{option:\(optionID)}}" }

    public var hasOption: Bool {
        !optionLabel.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var choices: [String] {
        optionChoices
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// - Parameter existing: Kennungen, die schon vergeben sind.
    public func problems(existing: Set<String> = []) -> [Problem] {
        var result: [Problem] = []
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(.titleMissing)
        }
        if instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(.instructionsMissing)
        }
        if existing.contains(identifier) {
            result.append(.identifierTaken)
        }
        if hasOption {
            if choices.count < 2 { result.append(.optionWithoutChoices) }
            if !instructions.contains(optionPlaceholder) { result.append(.optionNotUsed) }
        }
        return result
    }

    public func isReady(existing: Set<String> = []) -> Bool {
        !problems(existing: existing).contains(where: \.isBlocking)
    }

    // MARK: - Das fertige Werkzeug

    public func makeTool() -> AIPromptTool {
        AIPromptTool(
            id: identifier,
            title: title.trimmingCharacters(in: .whitespaces),
            subtitle: subtitle.trimmingCharacters(in: .whitespaces),
            systemImage: systemImage.isEmpty ? "wand.and.stars" : systemImage,
            categoryID: ToolCategory.custom.id,
            keywords: keywords
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
            promptTemplate: "{{input}}",
            options: hasOption && choices.count >= 2
                ? [
                    AIPromptOption(
                        id: optionID,
                        label: optionLabel.trimmingCharacters(in: .whitespaces),
                        choices: choices,
                        defaultValue: choices[0],
                        help: localized("Wird im Prompt für \(optionPlaceholder) eingesetzt.")
                    )
                ]
                : [],
            temperature: temperature,
            inputPlaceholder: inputPlaceholder.trimmingCharacters(in: .whitespaces)
        )
    }

    /// Die Datei, so wie sie auf der Platte stünde.
    ///
    /// Nicht bloß Schmuck: Wer sie sieht, weiß danach, wie die nächste von
    /// Hand aussieht — und genau das ist der Weg von „Formular ausgefüllt" zu
    /// „eigenes Werkzeug geschrieben".
    public func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(makeTool()),
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }

    /// Schreibt die Datei in den Ordner für eigene Werkzeuge.
    ///
    /// Überschrieben wird nur, was denselben Namen trägt — das ist beim
    /// Nachbessern genau richtig und beim Anlegen durch die Prüfung auf
    /// vergebene Kennungen ausgeschlossen.
    @discardableResult
    public func write(to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: fileName)
        let text = json()
        guard !text.isEmpty else {
            throw AnvilError.unexpected(localized("Das Werkzeug ließ sich nicht schreiben."))
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
