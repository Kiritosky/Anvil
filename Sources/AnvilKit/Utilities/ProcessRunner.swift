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

    /// Wie lange nach dem Ende des Programms noch auf das Ende seiner
    /// Ausgabe gewartet wird.
    ///
    /// Im Normalfall sind die Rohre längst zu, bevor die Frist überhaupt
    /// anläuft — sie greift nur, wenn ein Enkelprozess sie offen hält.
    static let gracePeriod: TimeInterval = 2

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

            // Fertig ist der Aufruf, wenn beide Rohre am Ende sind *und* das
            // Programm beendet ist. Vorher stand hier: Handler abhängen,
            // Rest lesen, zurückgeben — und wenn in genau dem Moment noch ein
            // Block unterwegs war, hängte der sich hinter den Rest und die
            // Ausgabe stand in falscher Reihenfolge da. Selten, aber bei
            // zwanzigtausend Zeilen aus `git` oder `unzip` reicht selten.
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

                // Rückfalltür: Ein Enkelprozess kann das Rohr offen halten,
                // nachdem sein Elternteil beendet ist — dann käme das Ende
                // nie. Nach einer Schonfrist wird geliefert, was da ist,
                // statt zu warten, bis jemand die App abschießt.
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
///
/// Drei Dinge müssen zusammenkommen, bevor ein Aufruf fertig ist: das Ende
/// der Standardausgabe, das Ende der Fehlerausgabe und das Ende des
/// Programms. Alle drei melden sich auf eigenen Warteschlangen und in
/// beliebiger Reihenfolge — deshalb zählt der Sammler mit, statt eine
/// Reihenfolge anzunehmen.
///
/// Das Ende eines Rohrs erkennt man daran, dass ein Lesen nichts mehr
/// liefert. Genau darauf zu warten ist der Unterschied zu „am Schluss den
/// Rest nachlesen": Ein Block, der beim Nachlesen noch unterwegs war, landete
/// dahinter statt davor.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var error = Data()
    private var outIsClosed = false
    private var errorIsClosed = false
    private var status: Int32?
    private var isFinished = false

    private let complete: (ProcessRunner.Result) -> Void

    init(complete: @escaping (ProcessRunner.Result) -> Void) {
        self.complete = complete
    }

    /// Liest, was da ist — und merkt sich, wenn nichts mehr kommt.
    func read(_ handle: FileHandle, isError: Bool) {
        let data = handle.availableData

        guard !data.isEmpty else {
            // Kein Byte mehr: Das Rohr ist zu. Der Handler muss weg, sonst
            // ruft das System ihn endlos mit demselben leeren Ergebnis.
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
        lock.unlock()
    }

    func exited(with status: Int32) {
        lock.lock()
        self.status = status
        let result = readyResult()
        lock.unlock()
        deliver(result)
    }

    /// Gibt auf und liefert, was da ist.
    ///
    /// Nur für den Fall, dass ein Rohr nach dem Ende des Programms offen
    /// bleibt. Ist der Aufruf längst fertig, passiert hier nichts.
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
    ///
    /// Wird unter dem Schloss gerufen; geliefert wird außerhalb, damit der
    /// Empfänger nicht unter einem fremden Schloss läuft.
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
