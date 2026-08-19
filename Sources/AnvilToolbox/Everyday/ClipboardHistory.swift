import AnvilKit
import AppKit
import Foundation
import Observation

/// One thing that was on the clipboard.
public struct ClipboardEntry: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let text: String
    public let copiedAt: Date
    /// The app that was in front when it was copied. Best effort — the
    /// clipboard itself does not record an owner.
    public let source: String?
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        copiedAt: Date = .now,
        source: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        self.source = source
        self.isPinned = isPinned
    }

    /// A single line for the list, whitespace collapsed.
    public var preview: String {
        let flattened = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(flattened.prefix(200))
    }

    public var lineCount: Int {
        TextLines.count(text)
    }
}

/// The clipboard, remembered.
@MainActor
@Observable
public final class ClipboardHistory {
    public private(set) var entries: [ClipboardEntry] = []
    public private(set) var isWatching = false

    @ObservationIgnored private let pasteboard: AnvilKit.Pasteboard
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var lastChangeCount: Int
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// Fast enough that copy-copy-paste is caught, slow enough to be free.
    private static let interval = Duration.milliseconds(700)

    public init(pasteboard: AnvilKit.Pasteboard, settings: SettingsStore) {
        self.pasteboard = pasteboard
        self.settings = settings
        self.lastChangeCount = pasteboard.changeCount
    }

    // MARK: - Watching

    public func start() {
        guard settings[.clipboardHistoryEnabled], pollTask == nil else { return }
        isWatching = true

        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard let self, !Task.isCancelled else { return }
                self.poll()
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        isWatching = false
    }

    /// Re-reads the setting and starts or stops accordingly.
    public func syncWatching() {
        settings[.clipboardHistoryEnabled] ? start() : stop()
    }

    /// One look at the clipboard. Public so the tool can force a check when it
    /// opens instead of waiting out the interval.
    public func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        guard !pasteboard.isConcealed() else { return }
        guard let text = pasteboard.string() else { return }

        record(text, source: NSWorkspace.shared.frontmostApplication?.localizedName)
    }

    // MARK: - Recording

    /// Adds `text` to the front of the history.
    public func record(_ text: String, source: String? = nil, at date: Date = .now) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = entries.firstIndex(where: { $0.text == text }) {
            let entry = entries.remove(at: existing)
            entries.insert(
                ClipboardEntry(
                    id: entry.id,
                    text: entry.text,
                    copiedAt: date,
                    source: entry.source ?? source,
                    isPinned: entry.isPinned
                ),
                at: 0
            )
            return
        }

        entries.insert(ClipboardEntry(text: text, copiedAt: date, source: source), at: 0)
        trim()
    }

    /// Drops the oldest unpinned entries once the limit is exceeded.
    private func trim() {
        let limit = max(10, settings[.clipboardHistoryLimit])
        var allowance = limit
        guard entries.filter({ !$0.isPinned }).count > limit else { return }

        entries = entries.filter { entry in
            if entry.isPinned { return true }
            guard allowance > 0 else { return false }
            allowance -= 1
            return true
        }
    }

    // MARK: - Using the history

    public func copy(_ entry: ClipboardEntry) {
        pasteboard.copy(entry.text)
        lastChangeCount = pasteboard.changeCount
        record(entry.text)
    }

    public func togglePin(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isPinned.toggle()
    }

    public func remove(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    /// Clears everything that is not pinned.
    public func clear() {
        entries = entries.filter(\.isPinned)
    }

    public func search(_ query: String) -> [ClipboardEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let matching = trimmed.isEmpty
            ? entries
            : entries.filter {
                $0.text.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }

        return matching.filter(\.isPinned) + matching.filter { !$0.isPinned }
    }
}

// MARK: - Settings keys

extension SettingKey {
    public static var clipboardHistoryEnabled: SettingKey<Bool> {
        SettingKey<Bool>("clipboard.enabled", default: true)
    }

    public static var clipboardHistoryLimit: SettingKey<Int> {
        SettingKey<Int>("clipboard.limit", default: 100)
    }
}

// MARK: - Tool context

extension ToolContext {
    /// The clipboard history, registered by the app at launch.
    public var clipboard: ClipboardHistory { require(ClipboardHistory.self) }
}
