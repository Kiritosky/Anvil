import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

/// Jede Variante jedes Katalog-Werkzeugs gegen alles, was jemand einwirft.
///
/// Der Grund, warum das ein eigener Test ist: Die Kataloge sind mit Abstand
/// die größte Fläche der App — über zwanzig Werkzeuge mit je einer Handvoll
/// Varianten, jede eine eigene kleine Rechnung auf fremdem Text. Geprüft wird
/// jede einzelne davon irgendwo, aber immer mit dem Text, für den sie gedacht
/// ist. Kaputt gehen sie am anderen: am leeren Feld, am Emoji, an der Zeile
/// mit dem Windows-Umbruch, an den zehntausend Zeichen aus der Zwischenablage.
///
/// Hier darf jedes Werkzeug werfen — ein Fehler ist eine Antwort. Was es nicht
/// darf, ist abstürzen, und genau das findet dieser Test: Ein Index daneben,
/// ein `first!` auf einer leeren Liste, ein Schnitt mitten durch ein Zeichen
/// nimmt die ganze App mit, und im Werkzeugkasten wäre es dann eine Kachel,
/// die den Rechner anhält.
@Suite("Kataloge gegen alles")
struct CatalogSmokeTests {
    /// Alles, was in einem Textfeld landen kann.
    private static let inputs: [String] = [
        "",
        " ",
        "\n",
        "\r\n",
        "\t",
        "hallo welt",
        "Straße Grüße ÄÖÜ",
        "😀👨‍👩‍👧‍👦🇩🇪",
        "42",
        "-1",
        "0",
        "3.14159",
        #"{"a": 1}"#,
        "[1, 2, 3]",
        "a,b,c",
        "a\nb\r\nc\rd",
        "https://anvil.dev/pfad?x=1&y=2",
        "<html>&amp;</html>",
        "-----BEGIN KEY-----",
        String(repeating: "x", count: 10_000),
        String(repeating: "ü", count: 1_000),
        "  führende und folgende Leerzeichen  "
    ]

    /// Werkzeuge, deren Antwort sich zwischen zwei Aufrufen ändern darf.
    ///
    /// Bei dreien ist der Zufall der Zweck, bei dreien die Uhr: Sie antworten
    /// über die Zeit, und die steht zwischen zwei Aufrufen nicht still. Jedes
    /// weitere in dieser Liste wäre ein Versehen.
    private static let changesOverTime: Set<String> = [
        "text.uuid", "everyday.password", "everyday.lorem",
        "text.timestamp", "everyday.timezones", "dev.cron"
    ]

    private static var catalogs: [(name: String, tools: [TextTool])] {
        [
            ("TextToolCatalog", TextToolCatalog.all),
            ("DevToolCatalog", DevToolCatalog.all),
            ("EverydayToolCatalog", EverydayToolCatalog.all)
        ]
    }

    /// Läuft jede Variante gegen jede Eingabe.
    ///
    /// Der Test besteht, wenn der Prozess bis zum Ende kommt — abstürzen darf
    /// keine davon. Geworfen werden darf, aber nur mit einem Fehler, den die
    /// Shell auch anzeigen kann.
    @Test
    func everyModeSurvivesEveryOrdinaryInput() {
        var runs = 0
        for catalog in Self.catalogs {
            for tool in catalog.tools {
                for mode in tool.modes {
                    for input in Self.inputs {
                        runs += 1
                        do {
                            _ = try tool.run(input, modeID: mode.id)
                        } catch {
                            #expect(
                                error is AnvilError,
                                "\(tool.id.rawValue)/\(mode.id) wirft \(type(of: error))"
                            )
                        }
                    }
                }
            }
        }
        // Wenn hier nichts mehr steht, hat sich ein Katalog geleert, ohne dass
        // es jemandem aufgefallen wäre.
        #expect(runs > 1_000)
    }

    /// Zweimal dasselbe hinein muss zweimal dasselbe herausgeben.
    ///
    /// Klingt selbstverständlich und ist es nicht: Wer eine UUID, ein Datum
    /// oder einen Zufallswert einbaut, hat ein Werkzeug gebaut, dessen
    /// Ergebnis man nicht vergleichen kann. Die, bei denen genau das der Zweck
    /// ist, stehen namentlich hier — jedes weitere wäre ein Versehen.
    @Test
    func everyModeGivesTheSameAnswerTwice() {
        for catalog in Self.catalogs {
            for tool in catalog.tools where !Self.changesOverTime.contains(tool.id.rawValue) {
                for mode in tool.modes {
                    let first = try? tool.run("Anvil 42", modeID: mode.id)
                    let second = try? tool.run("Anvil 42", modeID: mode.id)
                    #expect(first == second, "\(tool.id.rawValue)/\(mode.id)")
                }
            }
        }
    }

    /// Eine unbekannte Variante darf nicht ins Leere greifen.
    ///
    /// `run` nimmt die erste Variante, wenn die gesuchte fehlt — das passiert
    /// zur Laufzeit, sobald ein gemerkter Zustand auf ein Werkzeug trifft, das
    /// seine Varianten umbenannt hat.
    @Test
    func anUnknownModeFallsBackInsteadOfCrashing() {
        for catalog in Self.catalogs {
            for tool in catalog.tools where !Self.changesOverTime.contains(tool.id.rawValue) {
                guard let firstMode = tool.modes.first else { continue }
                let fallback = try? tool.run("Anvil", modeID: "gibt-es-nicht")
                let first = try? tool.run("Anvil", modeID: firstMode.id)
                #expect(fallback == first, "\(tool.id.rawValue)")
            }
        }
    }

    /// Jede Variante hat einen eigenen Namen — sonst wählt die Oberfläche
    /// beim Klick auf die zweite die erste.
    @Test
    func modeIdentifiersAreUniqueWithinATool() {
        for catalog in Self.catalogs {
            for tool in catalog.tools {
                var seen: Set<String> = []
                for mode in tool.modes {
                    #expect(
                        seen.insert(mode.id).inserted,
                        "\(tool.id.rawValue): \(mode.id) kommt doppelt vor"
                    )
                }
            }
        }
    }
}
