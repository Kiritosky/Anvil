import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

/// Der einzige Test, der den Werkzeugkasten als Ganzes ansieht.
///
/// Jeder andere Test prüft eine Rechnung. Hier geht es um das, was erst
/// auffällt, wenn alle Sammlungen nebeneinander liegen: zwei Werkzeuge mit
/// derselben Kennung, ein leerer Titel, ein Symbol, das es nicht gibt. Ohne
/// diesen Test fiele das erst beim Starten der App auf — und dann als
/// Werkzeug, das stumm fehlt, weil eine Registrierung die andere ersetzt hat.
@MainActor
@Suite("Der ganze Werkzeugkasten")
struct ToolboxTests {
    private var registrations: [ToolRegistration] {
        Toolbox.bundles.flatMap { $0.makeTools() }
    }

    private var metadata: [ToolMetadata] {
        registrations.map(\.metadata)
    }

    @Test
    func thereIsSomethingInEveryBundle() {
        for bundle in Toolbox.bundles {
            #expect(!bundle.makeTools().isEmpty, "\(bundle.displayName) ist leer")
        }
    }

    /// Eine doppelte Kennung ist kein Fehler, sondern eine Ersetzung: Die
    /// Registry behält die spätere. Ein Werkzeug verschwände also lautlos.
    @Test
    func noIdentifierIsUsedTwice() {
        var seen: Set<ToolIdentifier> = []
        for tool in metadata {
            #expect(seen.insert(tool.id).inserted, "\(tool.id.rawValue) kommt doppelt vor")
        }
    }

    @Test
    func noBundleIdentifierIsUsedTwice() {
        var seen: Set<String> = []
        for bundle in Toolbox.bundles {
            #expect(seen.insert(bundle.bundleIdentifier).inserted, "\(bundle.bundleIdentifier)")
        }
    }

    @Test
    func everyToolSaysWhatItIs() {
        for tool in metadata {
            #expect(!tool.title.isEmpty, "\(tool.id.rawValue)")
            #expect(!tool.subtitle.isEmpty, "\(tool.id.rawValue)")
            #expect(!tool.systemImage.isEmpty, "\(tool.id.rawValue)")
        }
    }

    /// Die Kennung landet in Favoriten, Verlauf und Fensterzustand — sie muss
    /// stabil und eindeutig aussehen, nicht wie ein Anzeigetext.
    @Test
    func everyIdentifierLooksLikeOne() {
        for tool in metadata {
            let raw = tool.id.rawValue
            #expect(raw.contains("."), "\(raw) hat keinen Namensraum")
            #expect(raw == raw.lowercased(), "\(raw) ist nicht klein geschrieben")
            #expect(!raw.contains(" "), "\(raw) enthält ein Leerzeichen")
        }
    }

    /// SF-Symbole heißen immer klein und mit Punkten. Ein falscher Name
    /// zeichnet nichts — und ein Werkzeug ohne Symbol sieht in der
    /// Seitenleiste aus wie ein Fehler.
    @Test
    func everySymbolLooksLikeAnSFSymbol() {
        for tool in metadata {
            let name = tool.systemImage
            #expect(
                name.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "." || $0 == "-" },
                "\(tool.id.rawValue): \(name)"
            )
        }
    }

    /// Der Suchkorpus ist das, woran die Palette ein Werkzeug findet. Ist er
    /// leer, ist das Werkzeug nur über die Seitenleiste erreichbar.
    @Test
    func everyToolCanBeFound() {
        for tool in metadata {
            #expect(tool.searchCorpus.count > tool.id.rawValue.count, "\(tool.id.rawValue)")
        }
    }

    /// Ein Werkzeug, das ein Sprachmodell braucht, muss das sagen — sonst
    /// erklärt die Shell nicht, warum es gerade nicht geht, sondern das
    /// Werkzeug scheitert erst beim Knopfdruck.
    @Test
    func everyAIToolSaysThatItNeedsAModel() {
        let ai = metadata.filter { $0.id.rawValue.hasPrefix("ai.") }
        #expect(!ai.isEmpty)
        for tool in ai {
            #expect(tool.usesAI, "\(tool.id.rawValue)")
        }
    }

    @Test
    func thereAreToolsInEveryShippedCategory() {
        let categories = Set(metadata.map(\.category))
        #expect(categories.count >= 3)
        for category in categories {
            #expect(metadata.contains { $0.category == category })
        }
    }

    /// Was Text annimmt, taucht im Weitergeben-Menü auf. Ein Werkzeug, das
    /// dort steht und mit dem Text nichts anfängt, wäre eine Sackgasse.
    @Test
    func someToolsAcceptText() {
        #expect(metadata.contains { $0.acceptsText })
    }

    /// Die Probe aufs Exempel: Nach der Registrierung müssen genau so viele
    /// Werkzeuge dastehen, wie die Sammlungen zusammen anmelden. Fehlt eines,
    /// hat eine Kennung die andere ersetzt — und niemand hätte es gemerkt.
    @Test
    func registeringEverythingLosesNothing() {
        let registry = ToolRegistry(settings: .ephemeral())
        for bundle in Toolbox.bundles {
            registry.register(bundle: bundle)
        }

        #expect(registry.allTools.count == registrations.count)
        for tool in registry.allTools {
            #expect(tool.origin.bundleIdentifier != ToolOrigin.unspecified.bundleIdentifier)
        }
    }
}
