import AnvilKit
import Foundation

/// A coding agent that is already installed and already signed in.
///
/// Claude Code, Codex and Gemini all ship a command that answers a single
/// prompt and prints the result. That is exactly the shape every tool in this
/// app needs — and it means no API key: the agent uses the subscription the
/// user already pays for, with its own credentials, in its own config.
///
/// The catch is finding the binary. A GUI app inherits `launchd`'s `PATH`,
/// which has none of the places these things install to, so the executable is
/// looked up through a login shell once and remembered.
public struct CLIAgentProvider: AIProvider, Sendable {
    /// The agents worth offering by name, and how each is called.
    public enum Agent: String, Codable, CaseIterable, Sendable, Identifiable {
        case claudeCode
        case codex
        case gemini
        /// Whatever the user typed.
        case custom

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .codex: "Codex"
            case .gemini: "Gemini CLI"
            case .custom: localized("Eigener Befehl")
            }
        }

        /// The command as installed.
        public var executable: String {
            switch self {
            case .claudeCode: "claude"
            case .codex: "codex"
            case .gemini: "gemini"
            case .custom: ""
            }
        }

        /// Arguments in front of the prompt. The prompt itself is appended as
        /// one argument — never interpolated into a shell string, or a
        /// transcript containing a backtick would run as a command.
        public var arguments: [String] {
            switch self {
            case .claudeCode: ["-p"]
            case .codex: ["exec", "--skip-git-repo-check"]
            case .gemini: ["-p"]
            case .custom: []
            }
        }

        public var explanation: String {
            switch self {
            case .claudeCode:
                localized("Nutzt deine Claude-Code-Anmeldung. Kein Schlüssel nötig.")
            case .codex:
                localized("Nutzt deine Codex-Anmeldung. Kein Schlüssel nötig.")
            case .gemini:
                localized("Nutzt deine Gemini-CLI-Anmeldung. Kein Schlüssel nötig.")
            case .custom:
                localized("Ein eigener Befehl, der den Prompt als letztes Argument bekommt und die Antwort ausgibt.")
            }
        }

        /// Roughly what the underlying model swallows. Generous, because all
        /// three sit in front of large-context models.
        public var inputBudget: Int {
            self == .custom ? 12_000 : 100_000
        }
    }

    public let agent: Agent
    /// Overrides for ``Agent/custom``, and for anyone whose binary is elsewhere.
    public let customExecutable: String
    public let customArguments: [String]
    /// Seconds before the agent is given up on. These are not fast.
    public let timeout: TimeInterval

    public init(
        agent: Agent,
        customExecutable: String = "",
        customArguments: [String] = [],
        timeout: TimeInterval = 180
    ) {
        self.agent = agent
        self.customExecutable = customExecutable
        self.customArguments = customArguments
        self.timeout = timeout
    }

    public var identifier: AIProviderIdentifier { .cliAgent }

    public var displayName: String { agent.title }

    /// The agent runs here, but it talks to a service. Honest is honest.
    public var runsOnDevice: Bool { false }

    public var approximateInputBudget: Int { agent.inputBudget }

    private var executableName: String {
        let custom = customExecutable.trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? agent.executable : custom
    }

    private var arguments: [String] {
        customArguments.isEmpty ? agent.arguments : customArguments
    }

    // MARK: - Availability

    public func availability() async -> AIAvailability {
        guard !executableName.isEmpty else {
            return .unavailable(.notConfigured)
        }
        guard await CLIAgentLocator.shared.path(for: executableName) != nil else {
            return .unavailable(.other(
                localized("„\(executableName)\" ist auf diesem Mac nicht installiert — oder liegt nicht im Pfad.")
            ))
        }
        return .available
    }

    // MARK: - Completing

    public func complete(_ request: AIRequest) async throws -> String {
        guard let path = await CLIAgentLocator.shared.path(for: executableName) else {
            throw AnvilError.modelUnavailable(
                localized("„\(executableName)\" wurde nicht gefunden. Installiert? Danach in den Einstellungen erneut suchen lassen.")
            )
        }

        // Instructions and prompt in one argument: these commands take a single
        // prompt, and a separate system prompt is not something all of them
        // have. The blank line keeps the two apart for the model.
        let prompt = request.instructions.isEmpty
            ? request.prompt
            : request.instructions + "\n\n" + request.prompt

        let runner = ProcessRunner()
        let result = try await runner.run(
            path,
            arguments: arguments + [prompt],
            environment: Self.environment,
            timeout: timeout
        )

        guard result.succeeded else {
            throw AnvilError.provider(
                localized("\(displayName) hat abgebrochen."),
                underlying: Self.firstLine(of: result.standardError)
            )
        }

        let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            throw AnvilError.provider(
                localized("\(displayName) hat nichts zurückgegeben."),
                underlying: nil
            )
        }
        return output
    }

    /// Passes the command's output through as it appears.
    ///
    /// Some of these agents print while they think and some hold everything
    /// until they exit; this makes the first kind feel live without pretending
    /// anything about the second.
    public func stream(_ request: AIRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard let path = await CLIAgentLocator.shared.path(for: executableName) else {
                    continuation.finish(throwing: AnvilError.modelUnavailable(
                        localized("„\(executableName)\" wurde nicht gefunden.")
                    ))
                    return
                }

                let prompt = request.instructions.isEmpty
                    ? request.prompt
                    : request.instructions + "\n\n" + request.prompt

                do {
                    let output = ProcessRunner().stream(
                        path,
                        arguments: arguments + [prompt],
                        environment: Self.environment,
                        timeout: timeout
                    )
                    for try await text in output {
                        continuation.yield(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    /// Enough environment for a Node- or Python-based CLI to find its own
    /// runtime, without inheriting whatever a GUI session happens to have.
    private static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = CLIAgentLocator.searchPath
        // These print progress and colour codes into stdout otherwise.
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        return environment
    }

    private static func firstLine(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let line = trimmed.components(separatedBy: .newlines).first, !line.isEmpty else {
            return localized("kein Fehlertext")
        }
        return String(line.prefix(200))
    }
}

/// Finds command-line agents once and remembers where they were.
///
/// A GUI app's `PATH` comes from `launchd` and contains none of the places npm,
/// Homebrew or pipx install to. Asking a login shell is the only way to see
/// what the user sees in Terminal — and it is slow enough to be worth caching.
public actor CLIAgentLocator {
    public static let shared = CLIAgentLocator()

    private var known: [String: String] = [:]

    /// The places these tools actually land, ahead of whatever was inherited.
    public static var searchPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let candidates = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.volta/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.claude/local",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return (candidates + [inherited]).joined(separator: ":")
    }

    /// The full path to `name`, or `nil` when it is not installed.
    public func path(for name: String) async -> String? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        if let known = known[name] { return known }

        // An absolute path the user typed themselves needs no searching.
        if name.hasPrefix("/") {
            guard FileManager.default.isExecutableFile(atPath: name) else { return nil }
            known[name] = name
            return name
        }

        for directory in Self.searchPath.split(separator: ":") {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                known[name] = candidate
                return candidate
            }
        }

        // Last resort: ask a login shell, which knows about version managers
        // that rewrite PATH in a profile.
        if let found = await askLoginShell(for: name) {
            known[name] = found
            return found
        }
        return nil
    }

    /// Forgets everything, so a freshly installed agent is found without a
    /// restart.
    public func forget() {
        known = [:]
    }

    private func askLoginShell(for name: String) async -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let runner = ProcessRunner()
        guard let result = try? await runner.run(
            shell,
            arguments: ["-l", "-c", "command -v \(name)"],
            timeout: 10
        ), result.succeeded else { return nil }

        let path = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }
}

extension AIProviderIdentifier {
    /// A coding agent installed on this Mac, driven through its command line.
    public static let cliAgent = AIProviderIdentifier("cli")
}
