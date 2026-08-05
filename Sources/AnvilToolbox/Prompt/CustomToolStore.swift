import AnvilKit
import Foundation

/// Loads user-written tools from disk.
///
/// A tool is one JSON file in `~/Library/Application Support/Anvil/Tools`. No
/// build step, no plug-in bundle, no signing — which is the only way "add your
/// own tool" is realistically going to happen on a Tuesday evening.
@MainActor
public final class CustomToolStore: ToolLibraryReloading {
    public static let bundleIdentifier = "dev.anvil.user"

    private let registry: ToolRegistry
    private let directory: URL

    public private(set) var lastLoadErrors: [String] = []

    public init(registry: ToolRegistry, directory: URL = AppPaths.customTools) {
        self.registry = registry
        self.directory = directory
    }

    public var userToolsDirectory: URL { directory }

    /// Re-reads every tool file and replaces the previously loaded set.
    @discardableResult
    public func reloadUserTools() -> Int {
        AppPaths.bootstrap()
        writeExampleIfEmpty()

        lastLoadErrors = []
        var registrations: [ToolRegistration] = []

        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        let decoder = JSONDecoder()
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where file.pathExtension.lowercased() == "json" {
            do {
                let data = try Data(contentsOf: file)
                let tool = try decoder.decode(AIPromptTool.self, from: data)
                let origin = ToolOrigin.userDefined(fileURL: file)
                registrations.append(AIToolBundle.registration(for: tool, origin: origin))
            } catch {
                // One malformed file must not take the rest of the folder down
                // with it; the Tool Store shows what failed and why.
                lastLoadErrors.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }

        registry.replaceTools(fromBundle: Self.bundleIdentifier, with: registrations)
        return registrations.count
    }

    /// Drops a documented example into an empty folder.
    ///
    /// Discovering that user tools exist at all is the hard part; a file that is
    /// already there and already works is the cheapest possible tutorial.
    private func writeExampleIfEmpty() {
        let existing = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        guard existing.isEmpty else { return }

        let example = AIPromptTool(
            id: "user.example",
            title: "Beispiel-Tool",
            subtitle: "Kopiervorlage für eigene Prompt-Tools",
            systemImage: "wand.and.stars",
            categoryID: ToolCategory.custom.id,
            keywords: ["beispiel", "vorlage", "eigenes tool"],
            instructions: """
            Du bist ein Werkzeug in Anvil. Antworte ausschließlich mit dem Ergebnis, \
            ohne Einleitung und ohne Rückfragen. Antworte in der Sprache der Eingabe.

            Aufgabe: Formuliere den Text so um, dass ihn jemand ohne Vorwissen versteht. \
            Ausführlichkeit: {{option:level}}.
            """,
            promptTemplate: "{{input}}",
            options: [
                AIPromptOption(
                    id: "level",
                    label: "Ausführlichkeit",
                    choices: ["knapp", "normal", "ausführlich"],
                    defaultValue: "normal",
                    help: "Wird im Prompt für {{option:level}} eingesetzt."
                )
            ],
            temperature: 0.4,
            inputPlaceholder: "Text, der einfacher werden soll …"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(example) else { return }
        try? data.write(to: directory.appending(path: "beispiel-tool.json"), options: .atomic)
    }
}
