import AnvilAI
import AnvilKit
import AnvilSpeech
import AppKit
import Carbon.HIToolbox
import Foundation
import Observation
import SwiftUI

/// Dictation from anywhere, without bringing the app forward.
///
/// Press the shortcut, talk, press it again. The text is cleaned up and — if
/// the cursor was sitting in a text field — typed straight in. Otherwise it
/// waits on the clipboard. The main window never opens.
@MainActor
@Observable
public final class QuickDictationController {
    public enum Phase: Equatable {
        case idle
        case starting
        case recording
        case refining
        /// Finished. `didPaste` decides which of the two confirmations shows.
        case delivered(didPaste: Bool)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    /// The shortcut currently registered, or `nil` when it is switched off.
    public private(set) var registeredShortcut: GlobalShortcut?
    /// Set when registration failed, e.g. because another app holds the keys.
    public private(set) var registrationError: String?

    @ObservationIgnored private let context: ToolContext
    @ObservationIgnored private let session = DictationSession()
    @ObservationIgnored private let refiner: TranscriptRefiner
    @ObservationIgnored private var panel: QuickDictationPanel?
    @ObservationIgnored private var previousApplication: NSRunningApplication?
    /// Where the caret was when the shortcut was pressed. Decided up front,
    /// because by the time the text is ready the answer would be about Anvil.
    @ObservationIgnored private var targetAcceptsText = false
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    private static let hotKeyOwner = "speech.quickDictation"
    private static let cancelHotKeyOwner = "speech.quickDictation.cancel"

    public init(context: ToolContext) {
        self.context = context
        self.refiner = TranscriptRefiner(router: context.ai)
    }

    // MARK: - Derived state

    public var levels: [Float] { session.levels }
    public var duration: TimeInterval { session.duration }
    public var isActive: Bool { phase != .idle }

    private var settings: SettingsStore { context.settings }

    // MARK: - Shortcut

    /// Registers or removes the global shortcut to match the current settings.
    public func syncShortcut() {
        registrationError = nil

        guard settings[.quickDictationEnabled], let shortcut = settings[.quickDictationShortcut] else {
            HotKeyCenter.shared.unregister(owner: Self.hotKeyOwner)
            registeredShortcut = nil
            return
        }

        do {
            try HotKeyCenter.shared.register(shortcut, owner: Self.hotKeyOwner) { [weak self] in
                self?.toggle()
            }
            registeredShortcut = shortcut
        } catch {
            registeredShortcut = nil
            registrationError = AnvilError.wrapping(error).message
        }
    }

    /// What the shortcut does: start if idle, finish if recording.
    public func toggle() {
        switch phase {
        case .idle, .delivered, .failed:
            Task { await start() }
        case .recording:
            Task { await finish() }
        case .starting, .refining:
            break
        }
    }

    /// Escape, claimed globally only while a dictation is running.
    ///
    /// The bubble deliberately never takes keyboard focus — that is what keeps
    /// the caret in the target app — so the only way to offer a keyboard cancel
    /// is to borrow the key for the few seconds it is needed.
    private func claimCancelKey() {
        let escape = GlobalShortcut(keyCode: UInt32(kVK_Escape), carbonModifiers: 0, keyLabel: "⎋")
        try? HotKeyCenter.shared.register(escape, owner: Self.cancelHotKeyOwner) { [weak self] in
            Task { await self?.cancel() }
        }
    }

    private func releaseCancelKey() {
        HotKeyCenter.shared.unregister(owner: Self.cancelHotKeyOwner)
    }

    // MARK: - Flow

    public func start() async {
        guard phase == .idle || isFinished else { return }

        dismissTask?.cancel()
        // Both of these have to be read before the bubble exists.
        previousApplication = NSWorkspace.shared.frontmostApplication
        targetAcceptsText = settings[.quickDictationPastes] && PasteService.focusedElementIsEditable()

        phase = .starting
        showBubble()

        await session.reset()
        await session.start(locale: locale, keepAudio: settings[.keepAudio])

        if let error = session.error {
            phase = .failed(error.message)
            scheduleDismiss(after: 3)
            return
        }

        phase = .recording
        claimCancelKey()
    }

    public func finish() async {
        guard phase == .recording else { return }
        releaseCancelKey()

        await session.stop()
        let raw = session.transcript.finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !raw.isEmpty else {
            phase = .failed(localized("Nichts verstanden."))
            scheduleDismiss(after: 2)
            return
        }

        phase = .refining
        let text = await cleanUp(raw)

        context.pasteboard.copy(text)

        if targetAcceptsText {
            await PasteService.paste(into: previousApplication)
        }
        phase = .delivered(didPaste: targetAcceptsText)
        scheduleDismiss(after: 1.1)
    }

    public func cancel() async {
        dismissTask?.cancel()
        releaseCancelKey()
        await session.discard()
        phase = .idle
        hideBubble()
    }

    // MARK: - Clean-up

    /// The deterministic pass always runs; the model only when it is switched
    /// on and available. Quick dictation must never hang waiting for a model.
    private func cleanUp(_ raw: String) async -> String {
        let cleaner = FillerCleaner(
            languageCode: locale.language.languageCode?.identifier ?? "de",
            strength: settings[.fillerStrength],
            collapsesRepeats: settings[.collapseRepeats]
        )
        let cleaned = cleaner.clean(raw).text

        guard settings[.useAIRefinement] else { return cleaned }

        do {
            return try await refiner.refine(
                cleaned,
                style: settings[.quickDictationStyle],
                languageName: session.catalog.displayName(for: locale),
                customInstruction: settings[.customRefinementInstruction]
            )
        } catch {
            // A model that cannot answer is not a reason to lose the dictation.
            return cleaned
        }
    }

    private var locale: Locale {
        let identifier = settings[.speechLocale]
        return identifier.isEmpty ? session.catalog.preferredLocale() : Locale(identifier: identifier)
    }

    private var isFinished: Bool {
        if case .delivered = phase { return true }
        if case .failed = phase { return true }
        return false
    }

    // MARK: - Bubble

    private func showBubble() {
        if panel == nil {
            panel = QuickDictationPanel(controller: self)
        }
        panel?.present()
    }

    private func hideBubble() {
        panel?.orderOut(nil)
        phase = .idle
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hideBubble()
        }
    }
}

// MARK: - Settings keys

extension SettingKey {
    public static var quickDictationEnabled: SettingKey<Bool> {
        SettingKey<Bool>("speech.quickDictation.enabled", default: false)
    }

    public static var quickDictationShortcut: SettingKey<GlobalShortcut?> {
        SettingKey<GlobalShortcut?>(
            "speech.quickDictation.shortcut",
            default: GlobalShortcut.defaultDictation
        )
    }

    public static var quickDictationStyle: SettingKey<RefinementStyle> {
        SettingKey<RefinementStyle>("speech.quickDictation.style", default: .verbatim)
    }

    /// Type the result into the focused text field. On by default: it is what
    /// the feature is for. Falls back to the clipboard whenever the focus is
    /// not editable, or the Accessibility permission is missing.
    public static var quickDictationPastes: SettingKey<Bool> {
        SettingKey<Bool>("speech.quickDictation.paste", default: true)
    }
}
