import Foundation

/// Runs a command-line tool and collects its output.
///
/// The app is not sandboxed, so tools may shell out — to `git` for diffs, to
/// `swift`/`node` for formatters. Everything goes through here so there is one
/// place that enforces timeouts and never invokes a shell (no string
/// interpolation into `sh -c`, therefore nothing to quote-escape wrong).
public struct ProcessRunner: Sendable {
    public struct Result: Sendable {
        public let exitCode: Int32
        public let standardOutput: String
        public let standardError: String

        public var succeeded: Bool { exitCode == 0 }

        /// stdout when the command succeeded, otherwise the best error text.
        public func outputOrThrow() throws -> String {
            guard succeeded else {
                let detail = standardError.isEmpty ? standardOutput : standardError
                throw AnvilError.unexpected(
                    detail.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            return standardOutput
        }
    }

    public init() {}

    /// Runs `executable` with `arguments`, returning once it exits.
    ///
    /// - Parameters:
    ///   - executable: Absolute path, or a bare name resolved through `/usr/bin/env`.
    ///   - workingDirectory: Directory to run in.
    ///   - timeout: Seconds before the process is terminated.
    public func run(
        _ executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval = 30
    ) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            if executable.hasPrefix("/") {
                process.executableURL = URL(filePath: executable)
                process.arguments = arguments
            } else {
                process.executableURL = URL(filePath: "/usr/bin/env")
                process.arguments = [executable] + arguments
            }
            process.currentDirectoryURL = workingDirectory
            if let environment { process.environment = environment }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let state = OutputCollector()
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                state.appendOut(handle.availableData)
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                state.appendError(handle.availableData)
            }

            process.terminationHandler = { finished in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                state.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
                state.appendError(errPipe.fileHandleForReading.readDataToEndOfFile())
                guard state.finish() else { return }
                continuation.resume(
                    returning: Result(
                        exitCode: finished.terminationStatus,
                        standardOutput: state.outText,
                        standardError: state.errorText
                    )
                )
            }

            do {
                try process.run()
            } catch {
                guard state.finish() else { return }
                continuation.resume(throwing: AnvilError.unexpected(
                    localized("\(executable) konnte nicht gestartet werden: \(error.localizedDescription)")
                ))
                return
            }

            let deadline = DispatchTime.now() + timeout
            DispatchQueue.global().asyncAfter(deadline: deadline) {
                if process.isRunning { process.terminate() }
            }
        }
    }

    /// Convenience for `git` in a repository.
    public func git(
        _ arguments: [String],
        in repository: URL,
        timeout: TimeInterval = 20
    ) async throws -> String {
        let result = try await run("git", arguments: arguments, workingDirectory: repository, timeout: timeout)
        return try result.outputOrThrow()
    }
}

/// Serialises pipe reads and guarantees the continuation resumes exactly once.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var error = Data()
    private var finished = false

    func appendOut(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); out.append(data); lock.unlock()
    }

    func appendError(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); error.append(data); lock.unlock()
    }

    /// Returns `true` for the first caller only.
    func finish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if finished { return false }
        finished = true
        return true
    }

    var outText: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: out, as: UTF8.self)
    }

    var errorText: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: error, as: UTF8.self)
    }
}

extension ProcessRunner {
    /// Runs a command and hands back its output as it arrives.
    ///
    /// Each element is the *cumulative* standard output so far, not a delta —
    /// the same contract the model providers use, so a view can bind straight
    /// to the latest value.
    ///
    /// Whether this actually produces more than one element is up to the
    /// command: one that buffers until it exits yields once, at the end. That
    /// is a property of the program, not a bug here.
    public func stream(
        _ executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval = 30
    ) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            if executable.hasPrefix("/") {
                process.executableURL = URL(filePath: executable)
                process.arguments = arguments
            } else {
                process.executableURL = URL(filePath: "/usr/bin/env")
                process.arguments = [executable] + arguments
            }
            process.currentDirectoryURL = workingDirectory
            if let environment { process.environment = environment }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let state = OutputCollector()
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                state.appendOut(data)
                continuation.yield(state.outText)
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                state.appendError(handle.availableData)
            }

            process.terminationHandler = { finished in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                state.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
                state.appendError(errPipe.fileHandleForReading.readDataToEndOfFile())
                guard state.finish() else { return }

                guard finished.terminationStatus == 0 else {
                    continuation.finish(throwing: AnvilError.provider(
                        localized("\(executable) ist mit Fehler \(Int(finished.terminationStatus)) beendet worden."),
                        underlying: state.errorText.isEmpty ? nil : state.errorText
                    ))
                    return
                }

                continuation.yield(state.outText)
                continuation.finish()
            }

            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }

            do {
                try process.run()
            } catch {
                guard state.finish() else { return }
                continuation.finish(throwing: AnvilError.unexpected(
                    localized("\(executable) konnte nicht gestartet werden: \(error.localizedDescription)")
                ))
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}
