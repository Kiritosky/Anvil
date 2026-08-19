import AnvilKit
import Foundation

/// Fragt `git` nach dem Zustand eines Repositories.
public struct GitReader: Sendable {
    private let runner = ProcessRunner()

    public init() {}

    /// Umgebung, die `git` daran hindert, auf eine Eingabe zu warten.
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
    public func read(_ repository: URL) async -> GitRepository {
        do {
            let status = try await status(of: repository)
            let branches = (try? await branches(of: repository)) ?? []
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
    public static let batchSize = 8

    /// Liest einen Schwung Repositories nebenläufig.
    public func read(_ repositories: [URL]) async -> [GitRepository] {
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
    public func fetch(_ repository: URL) async throws {
        _ = try await git(["fetch", "--all", "--prune"], in: repository, timeout: 120)
    }

    /// Holt einen Schwung Repositories nebenläufig.
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
