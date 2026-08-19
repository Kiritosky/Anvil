import Foundation

/// The error type the shell knows how to present.
public enum AnvilError: LocalizedError, Sendable {
    /// No language model is usable right now.
    case modelUnavailable(String)
    /// A provider rejected the request or the network failed.
    case provider(String, underlying: String?)
    /// Microphone or speech-recognition permission is missing.
    case permissionDenied(String)
    /// Reading or writing on disk / in the keychain failed.
    case storage(String)
    /// The input a tool was given cannot be processed.
    case invalidInput(String)
    /// The user cancelled.
    case cancelled
    /// Anything else.
    case unexpected(String)

    public var errorDescription: String? { message }

    public var title: String {
        switch self {
        case .modelUnavailable: localized("Kein Modell verfügbar")
        case .provider: localized("Anbieter-Fehler")
        case .permissionDenied: localized("Berechtigung fehlt")
        case .storage: localized("Speicher-Fehler")
        case .invalidInput: localized("Eingabe passt nicht")
        case .cancelled: localized("Abgebrochen")
        case .unexpected: localized("Unerwarteter Fehler")
        }
    }

    public var message: String {
        switch self {
        case let .modelUnavailable(text): text
        case let .provider(text, underlying):
            underlying.map { "\(text)\n\n\($0)" } ?? text
        case let .permissionDenied(text): text
        case let .storage(text): text
        case let .invalidInput(text): text
        case .cancelled: localized("Der Vorgang wurde abgebrochen.")
        case let .unexpected(text): text
        }
    }

    /// A short, actionable hint shown under the message, when one exists.
    public var recoverySuggestion: String? {
        switch self {
        case .modelUnavailable:
            localized("Aktiviere Apple Intelligence in den Systemeinstellungen oder hinterlege in den Anvil-Einstellungen einen externen Anbieter.")
        case .permissionDenied:
            localized("Erlaube den Zugriff unter Systemeinstellungen › Datenschutz & Sicherheit.")
        case .provider:
            localized("Prüfe API-Schlüssel, Modellnamen und Netzwerkverbindung in den Einstellungen.")
        default:
            nil
        }
    }

    public var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }

    /// Normalises an arbitrary error, preserving cancellation.
    public static func wrapping(_ error: any Error) -> AnvilError {
        if let anvil = error as? AnvilError { return anvil }
        if error is CancellationError { return .cancelled }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return .cancelled
        }
        return .unexpected(error.localizedDescription)
    }
}
