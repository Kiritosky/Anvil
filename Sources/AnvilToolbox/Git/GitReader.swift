import AnvilKit
import Foundation

/// Fragt `git` nach dem Zustand eines Repositories.
///
/// Alles hier ist lesend, bis auf ``fetch(_:)``. Das ist Absicht: Ein Werkzeug,
/// das über dreißig Repositories läuft, darf in keinem davon etwas verändern,
/// was man nicht ausdrücklich angestoßen hat. Selbst `fetch` schreibt nur in
/// die Remote-Referenzen und rührt weder Arbeitsverzeichnis noch eigene Zweige
/// an.
public struct GitReader: Sendable {
    private let runner = ProcessRunner()

    public init() {}

    /// Umgebung, die `git` daran hindert, auf eine Eingabe zu warten.
    ///
    /// Ohne das bleibt der erste Fetch auf ein privates Repository stehen und
    /// wartet auf ein Passwort, das niemand eingeben kann — die App hat kein
    /// Terminal. Es dauert dann so lange, bis die Zeitgrenze greift, und
    /// dreißig Repositories später hat der Benutzer die App weggeklickt.
    private var quietEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_ASKPASS"] = "/usr/bin/true"
        environment["SSH_ASKPASS"] = "/usr/bin/true"
        return environment
    }

    private func git(
        _ arguments: [String],
        in repository: URL,
        timeout: TimeInterval = 20
    ) async throws -> String {
        let result = try await runner.run(
            "git",
            arguments: arguments,
            workingDirectory: repository,
            environment: quietEnvironment,
            timeout: timeout
        )
        return try result.outputOrThrow()
    }

    /// Ob auf diesem Mac überhaupt ein `git` liegt.
    public func isAvailable() async -> Bool {
        let result = try? await runner.run("git", arguments: ["--version"], timeout: 5)
        return result?.succeeded ?? false
    }

    // MARK: - Ein Repository

    public func status(of repository: URL) async throws -> GitStatus {
        GitStatus(porcelain: try await git(["status", "--porcelain", "--branch"], in: repository))
    }

    public func branches(of repository: URL) async throws -> [GitBranch] {
        let output = try await git(
            ["for-each-ref", "--format=" + GitBranch.refFormat, "refs/heads"],
            in: repository
        )
        return GitBranch.list(output)
    }

    /// Der letzte Commit — oder nichts, wenn es noch keinen gibt.
    public func lastCommit(of repository: URL) async throws -> GitCommit? {
        let output = try await git(
            ["log", "-1", "--format=" + GitCommit.logFormat],
            in: repository
        )
        return GitCommit.read(output)
    }

    /// Alles über ein Repository, ohne zu werfen.
    ///
    /// Ein Repository, in dem `git` scheitert — kaputtes Verzeichnis, fremder
    /// Besitzer, `dubious ownership` —, darf die Übersicht über die anderen
    /// neunundzwanzig nicht verhindern. Der Fehler steht dann in der Zeile.
    public func read(_ repository: URL) async -> GitRepository {
        do {
            let status = try await status(of: repository)
            let branches = (try? await branches(of: repository)) ?? []
            // Ein frisches Repository hat noch keinen Commit; `git log`
            // scheitert dann, und das ist keine Störung, sondern die Auskunft.
            let commit = try? await lastCommit(of: repository)
            return GitRepository(
                url: repository,
                status: status,
                branches: branches,
                lastCommit: commit
            )
        } catch {
            return GitRepository(
                url: repository,
                status: GitStatus(branch: nil, upstream: nil),
                failure: AnvilError.wrapping(error).message
            )
        }
    }

    // MARK: - Viele Repositories

    /// Wie viele Repositories gleichzeitig gelesen werden.
    ///
    /// Jedes davon ist ein eigener Prozess. Alle auf einmal zu starten wäre bei
    /// zweihundert Repositories nicht schneller, sondern langsamer — und
    /// zwischendurch stünde die Anzeige still, weil niemand berichten kann,
    /// was schon fertig ist.
    public static let batchSize = 8

    /// Liest einen Schwung Repositories nebenläufig.
    ///
    /// Die Aufrufstelle geht in Schwüngen durch die Liste; so kann sie nach
    /// jedem Schwung anzeigen, wie weit es ist, und abbrechen, wenn der
    /// Benutzer weiterklickt.
    public func read(_ repositories: [URL]) async -> [GitRepository] {
        // `TaskGroup` liefert, was zuerst fertig wird — eine Liste, die bei
        // jedem Durchlauf anders sortiert ist, kann man nicht lesen. Deshalb
        // wird am Ende nach der Eingabereihenfolge wieder einsortiert.
        var byPath: [String: GitRepository] = [:]

        await withTaskGroup(of: GitRepository.self) { group in
            for repository in repositories {
                group.addTask { await self.read(repository) }
            }
            for await result in group {
                byPath[result.url.path] = result
            }
        }

        return repositories.compactMap { byPath[$0.path] }
    }

    // MARK: - Holen

    /// `git fetch --prune` in einem Repository.
    ///
    /// `--prune` ist der Punkt der Übung: Erst danach weiß das Repository, dass
    /// ein Zweig auf dem Server gelöscht wurde, und erst dann lässt sich sagen,
    /// welcher lokale Zweig aufgeräumt werden kann.
    public func fetch(_ repository: URL) async throws {
        _ = try await git(["fetch", "--all", "--prune"], in: repository, timeout: 120)
    }

    /// Holt einen Schwung Repositories nebenläufig.
    ///
    /// Ein `fetch` wartet fast die ganze Zeit auf den Server. Dreißig davon
    /// nacheinander sind dreißigmal diese Wartezeit, obwohl der Mac dabei
    /// nichts tut — nebenläufig ist es der Schwung, der am längsten braucht.
    ///
    /// - Returns: Die Repositories, bei denen es nicht ging.
    public func fetch(_ repositories: [URL]) async -> [URL] {
        await withTaskGroup(of: URL?.self) { group in
            for repository in repositories {
                group.addTask {
                    do {
                        try await self.fetch(repository)
                        return nil
                    } catch {
                        return repository
                    }
                }
            }

            var failed: [URL] = []
            for await result in group {
                if let result { failed.append(result) }
            }
            return failed
        }
    }
}
