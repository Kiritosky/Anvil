import AnvilKit
import Foundation
import Observation
import Speech

/// Which languages the on-device transcriber can handle, and which ones are
/// actually installed on this Mac.
///
/// Speech assets are downloaded per language and have to be *reserved* before
/// use. Getting that wrong is the single most common reason live transcription
/// silently produces nothing, so it all lives in one place.
@MainActor
@Observable
public final class TranscriptionModelCatalog {
    public private(set) var supportedLocales: [Locale] = []
    public private(set) var installedLocales: [Locale] = []
    public private(set) var isPreparing = false
    public private(set) var downloadProgress: Double?
    public private(set) var lastError: AnvilError?

    public init() {}

    /// Loads the supported and installed lists. Cheap enough to call on appear.
    public func refresh() async {
        let supported = await SpeechTranscriber.supportedLocales
        let installed = await SpeechTranscriber.installedLocales

        supportedLocales = supported.sorted { lhs, rhs in
            displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs))
                == .orderedAscending
        }
        installedLocales = installed
    }

    public func isSupported(_ locale: Locale) -> Bool {
        supportedLocales.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    public func isInstalled(_ locale: Locale) -> Bool {
        installedLocales.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    /// Picks a sensible default: the user's own language if the transcriber
    /// speaks it, then German, then English, then whatever is first.
    public func preferredLocale() -> Locale {
        let candidates = [Locale.current, Locale(identifier: "de-DE"), Locale(identifier: "en-US")]
        for candidate in candidates where isSupported(candidate) {
            return candidate
        }
        return supportedLocales.first ?? Locale(identifier: "en-US")
    }

    public func displayName(for locale: Locale) -> String {
        let name = Locale.current.localizedString(forIdentifier: locale.identifier)
        return name ?? locale.identifier
    }

    /// Downloads the assets for `transcriber` if needed and reserves its locale.
    ///
    /// - Throws: ``AnvilError`` when the language is unsupported or the download
    ///   fails, so callers can show the reason instead of an empty transcript.
    public func prepare(transcriber: SpeechTranscriber, locale: Locale) async throws {
        isPreparing = true
        downloadProgress = nil
        lastError = nil
        defer {
            isPreparing = false
            downloadProgress = nil
        }

        do {
            if supportedLocales.isEmpty { await refresh() }

            guard isSupported(locale) else {
                throw AnvilError.invalidInput(
                    localized("\(displayName(for: locale)) wird von der Spracherkennung auf diesem Mac nicht unterstützt.")
                )
            }

            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                let progress = request.progress
                let observation = Task { @MainActor in
                    while !Task.isCancelled, !progress.isFinished {
                        downloadProgress = progress.fractionCompleted
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
                defer { observation.cancel() }
                try await request.downloadAndInstall()
            }

            try await reserve(locale)
            await refresh()
        } catch let error as AnvilError {
            lastError = error
            throw error
        } catch {
            let wrapped = AnvilError.unexpected(
                localized("Die Sprachdaten konnten nicht geladen werden: \(error.localizedDescription)")
            )
            lastError = wrapped
            throw wrapped
        }
    }

    /// Reserves a locale, which the analyser requires before it will run.
    private func reserve(_ locale: Locale) async throws {
        let reserved = await AssetInventory.reservedLocales
        if reserved.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            return
        }
        try await AssetInventory.reserve(locale: locale)
    }

    /// Gives back every reserved locale. Reservations are a limited resource,
    /// so the app releases them when the last speech tool closes.
    public func releaseAll() async {
        for locale in await AssetInventory.reservedLocales {
            await AssetInventory.release(reservedLocale: locale)
        }
    }
}
