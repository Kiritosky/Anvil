import Foundation
import Testing

@testable import AnvilKit

/// Der Weg, über den Anvil fremde Programme startet — Git für Diffs, die
/// Coding-Agenten fürs Modell.
///
/// Getestet wird mit `/bin/sh -c`, weil das auf jedem Mac liegt und sich dazu
/// bringen lässt, genau das zu tun, was hier interessiert: schreiben, sich
/// beschweren, scheitern, hängenbleiben.
@Suite("ProcessRunner")
struct ProcessRunnerTests {
    private let runner = ProcessRunner()

    // MARK: - Der Normalfall

    @Test
    func collectsStandardOutput() async throws {
        let result = try await runner.run("/bin/sh", arguments: ["-c", "printf 'hallo'"])
        #expect(result.succeeded)
        #expect(result.standardOutput == "hallo")
        #expect(result.standardError.isEmpty)
    }

    /// Beide Ströme getrennt: sonst landet eine Warnung mitten im Ergebnis.
    @Test
    func keepsOutputAndErrorApart() async throws {
        let result = try await runner.run(
            "/bin/sh",
            arguments: ["-c", "printf 'ergebnis'; printf 'warnung' >&2"]
        )
        #expect(result.standardOutput == "ergebnis")
        #expect(result.standardError == "warnung")
    }

    /// Mehr, als in einen Rohrpuffer passt. Ohne das laufende Mitlesen bliebe
    /// das Programm beim Schreiben stehen und der Aufruf käme nie zurück —
    /// der Klassiker bei genau dieser Art Code.
    @Test
    func readsMoreThanAPipeBufferHolds() async throws {
        let result = try await runner.run(
            "/bin/sh",
            arguments: ["-c", "for i in $(seq 1 20000); do echo Zeile$i; done"],
            timeout: 30
        )
        #expect(result.succeeded)
        #expect(result.standardOutput.count > 128 * 1024)
        #expect(result.standardOutput.hasSuffix("Zeile20000\n"))
    }

    /// Nicht nur vollständig, sondern auch in der richtigen Reihenfolge.
    ///
    /// Der Fall, den die Prüfung auf die letzte Zeile allein durchgehen ließ:
    /// Wer am Ende den Rest nachliest, während noch ein Block unterwegs ist,
    /// bekommt alles — nur eben nicht der Reihe nach. Das fällt bei einer
    /// Dateiliste aus `unzip` erst auf, wenn eine Zeile mitten in einer
    /// anderen steht.
    @Test
    func everyLineArrivesInOrder() async throws {
        let result = try await runner.run(
            "/bin/sh",
            arguments: ["-c", "for i in $(seq 1 20000); do echo Zeile$i; done"],
            timeout: 30
        )

        let lines = result.standardOutput.split(separator: "\n")
        #expect(lines.count == 20_000)
        #expect(lines.first == "Zeile1")
        #expect(lines.last == "Zeile20000")

        let outOfOrder = lines.enumerated()
            .first { $0.element != "Zeile\($0.offset + 1)" }?
            .element
        #expect(outOfOrder == nil)
    }

    // MARK: - Wenn es schiefgeht

    @Test
    func reportsTheExitCode() async throws {
        let result = try await runner.run("/bin/sh", arguments: ["-c", "exit 3"])
        #expect(!result.succeeded)
        #expect(result.exitCode == 3)
    }

    @Test
    func missingExecutableThrows() async {
        await #expect(throws: AnvilError.self) {
            try await runner.run("/gibt/es/nicht/anvil", arguments: [])
        }
    }

    /// `outputOrThrow` nimmt den Fehlertext, wenn es einen gibt — und sonst,
    /// was auf stdout stand. Ein Programm, das seinen Fehler nach stdout
    /// schreibt, ist häufiger als einem lieb ist.
    @Test
    func outputOrThrowPrefersTheErrorText() async throws {
        let withError = try await runner.run(
            "/bin/sh",
            arguments: ["-c", "printf 'auf stdout'; printf 'der eigentliche Fehler' >&2; exit 1"]
        )
        #expect(throws: AnvilError.self) { try withError.outputOrThrow() }

        let quiet = try await runner.run("/bin/sh", arguments: ["-c", "printf 'nur hier'; exit 1"])
        #expect(throws: AnvilError.self) { try quiet.outputOrThrow() }

        let fine = try await runner.run("/bin/sh", arguments: ["-c", "printf 'gut'"])
        let output = try fine.outputOrThrow()
        #expect(output == "gut")
    }

    // MARK: - Zeitlimit

    /// Der Grund, warum es diesen Typ gibt: ein Programm, das nicht zurückkommt,
    /// darf die App nicht mitnehmen.
    @Test
    func aHangingProcessIsTerminated() async throws {
        let started = Date()
        let result = try await runner.run("/bin/sh", arguments: ["-c", "sleep 30"], timeout: 2)
        let elapsed = Date().timeIntervalSince(started)

        #expect(elapsed < 10, "Das Zeitlimit hat nicht gegriffen")
        #expect(!result.succeeded)
    }

    // MARK: - Umgebung und Verzeichnis

    @Test
    func runsInTheGivenDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "anvil-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await runner.run(
            "/bin/sh",
            arguments: ["-c", "pwd"],
            workingDirectory: directory
        )
        // Das temporäre Verzeichnis liegt hinter einem Symlink; verglichen wird
        // deshalb der letzte Teil, nicht der ganze Pfad.
        #expect(result.standardOutput.contains(directory.lastPathComponent))
    }

    @Test
    func passesTheGivenEnvironment() async throws {
        let result = try await runner.run(
            "/bin/sh",
            arguments: ["-c", "printf '%s' \"$ANVIL_TEST\""],
            environment: ["ANVIL_TEST": "gesetzt", "PATH": "/usr/bin:/bin"]
        )
        #expect(result.standardOutput == "gesetzt")
    }

    /// Argumente gehen als Liste an das Programm, nie durch eine Shell. Sonst
    /// würde ein Backtick in einem Transkript zu einem Befehl.
    @Test
    func argumentsAreNeverInterpretedByAShell() async throws {
        let dangerous = "`touch /tmp/anvil-should-not-exist`; $(whoami)"
        let result = try await runner.run("/bin/echo", arguments: [dangerous])

        #expect(result.standardOutput.contains("`touch"))
        #expect(!FileManager.default.fileExists(atPath: "/tmp/anvil-should-not-exist"))
    }
}
