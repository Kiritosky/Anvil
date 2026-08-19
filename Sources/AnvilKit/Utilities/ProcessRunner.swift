import Foundation

/// Runs a command-line tool and collects its output.
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

    /// Wie lange nach dem Ende des Programms noch auf das Ende seiner
    /// Ausgabe gewartet wird.
    static let gracePeriod: TimeInterval = 2

    /// Runs `executable` with `arguments`, returning once it exits.
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

            let state = OutputCollector { result in
                continuation.resume(returning: result)
            }

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                state.read(handle, isError: false)
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                state.read(handle, isError: true)
            }

            process.terminationHandler = { finished in
                state.exited(with: finished.terminationStatus)

                DispatchQueue.global().asyncAfter(deadline: .now() + Self.gracePeriod) {
                    state.giveUp(
                        out: outPipe.fileHandleForReading,
                        error: errPipe.fileHandleForReading
                    )
                }
            }

            do {
                try process.run()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                guard state.claim() else { return }
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

/// Sammelt die Ausgabe eines Prozesses und gibt sie genau einmal zurück.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var error = Data()
    private var outIsClosed = false
    private var errorIsClosed = false
    private var status: Int32?
    private var isFinished = false

    private let complete: (ProcessRunner.Result) -> Void
    /// Wird nach jedem Block gerufen, mit allem, was bisher da ist.
    private let onOutput: ((String) -> Void)?

    init(
        onOutput: ((String) -> Void)? = nil,
        complete: @escaping (ProcessRunner.Result) -> Void
    ) {
        self.onOutput = onOutput
        self.complete = complete
    }

    /// Liest, was da ist — und merkt sich, wenn nichts mehr kommt.
    func read(_ handle: FileHandle, isError: Bool) {
        let data = handle.availableData

        guard !data.isEmpty else {
            handle.readabilityHandler = nil
            lock.lock()
            if isError { errorIsClosed = true } else { outIsClosed = true }
            let result = readyResult()
            lock.unlock()
            deliver(result)
            return
        }

        lock.lock()
        if isError { error.append(data) } else { out.append(data) }
        let snapshot = isError || onOutput == nil
            ? nil
            : String(decoding: out, as: UTF8.self)
        lock.unlock()

        if let snapshot { onOutput?(snapshot) }
    }

    func exited(with status: Int32) {
        lock.lock()
        self.status = status
        let result = readyResult()
        lock.unlock()
        deliver(result)
    }

    /// Gibt auf und liefert, was da ist.
    func giveUp(out: FileHandle, error: FileHandle) {
        out.readabilityHandler = nil
        error.readabilityHandler = nil

        lock.lock()
        outIsClosed = true
        errorIsClosed = true
        let result = readyResult()
        lock.unlock()
        deliver(result)
    }

    /// Nimmt das Ergebnis in Beschlag, ohne eines zu liefern — für den Fall,
    /// dass sich das Programm gar nicht erst starten ließ.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isFinished { return false }
        isFinished = true
        return true
    }

    /// Das Ergebnis, wenn alles beisammen ist — und nur beim ersten Mal.
    private func readyResult() -> ProcessRunner.Result? {
        guard !isFinished, outIsClosed, errorIsClosed, let status else { return nil }
        isFinished = true
        return ProcessRunner.Result(
            exitCode: status,
            standardOutput: String(decoding: out, as: UTF8.self),
            standardError: String(decoding: error, as: UTF8.self)
        )
    }

    private func deliver(_ result: ProcessRunner.Result?) {
        guard let result else { return }
        complete(result)
    }
}

extension ProcessRunner {
    /// Runs a command and hands back its output as it arrives.
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

            let state = OutputCollector { text in
                continuation.yield(text)
            } complete: { result in
                guard result.exitCode == 0 else {
                    let statusCode = Int(result.exitCode)
                    continuation.finish(throwing: AnvilError.provider(
                        localized("\(executable) ist mit Fehler \(statusCode) beendet worden."),
                        underlying: result.standardError.isEmpty ? nil : result.standardError
                    ))
                    return
                }

                continuation.yield(result.standardOutput)
                continuation.finish()
            }

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                state.read(handle, isError: false)
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                state.read(handle, isError: true)
            }

            process.terminationHandler = { finished in
                state.exited(with: finished.terminationStatus)

                DispatchQueue.global().asyncAfter(deadline: .now() + Self.gracePeriod) {
                    state.giveUp(
                        out: outPipe.fileHandleForReading,
                        error: errPipe.fileHandleForReading
                    )
                }
            }

            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }

            do {
                try process.run()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                guard state.claim() else { return }
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
