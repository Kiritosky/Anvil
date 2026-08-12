import Foundation
import Observation

/// One saved run of a tool.
public struct HistoryEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let toolID: ToolIdentifier
    public var title: String
    public var input: String
    public var output: String
    public let createdAt: Date
    /// Free-form extras (style used, locale, model name, …).
    public var attributes: [String: String]

    public init(
        id: UUID = UUID(),
        toolID: ToolIdentifier,
        title: String,
        input: String,
        output: String,
        createdAt: Date = .now,
        attributes: [String: String] = [:]
    ) {
        self.id = id
        self.toolID = toolID
        self.title = title
        self.input = input
        self.output = output
        self.createdAt = createdAt
        self.attributes = attributes
    }

    public var preview: String {
        let source = output.isEmpty ? input : output
        let flattened = source
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flattened.count > 140 ? String(flattened.prefix(140)) + "…" : flattened
    }
}

/// Per-tool run history, one JSON file per tool.
///
/// Entries are loaded lazily and cached, so a tool that never asks for its
/// history costs nothing. Writes are debounced to the end of the run loop turn
/// by simply writing synchronously on the main actor — history files are tiny.
@MainActor
@Observable
public final class HistoryStore {
    @ObservationIgnored private let directory: URL
    /// Read on every write so that changing it in Settings takes effect at
    /// once instead of at the next launch.
    @ObservationIgnored private let limitProvider: () -> Int
    @ObservationIgnored private let encoder: JSONEncoder
    @ObservationIgnored private let decoder = JSONDecoder()

    private var cache: [ToolIdentifier: [HistoryEntry]] = [:]

    public init(directory: URL = AppPaths.history, limit: @escaping @autoclosure () -> Int = 50) {
        self.directory = directory
        self.limitProvider = limit
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func entries(for toolID: ToolIdentifier) -> [HistoryEntry] {
        if let cached = cache[toolID] { return cached }
        let loaded = load(toolID)
        cache[toolID] = loaded
        return loaded
    }

    @discardableResult
    public func record(_ entry: HistoryEntry) -> HistoryEntry {
        var entries = entries(for: entry.toolID)
        entries.insert(entry, at: 0)
        let limit = max(1, limitProvider())
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        cache[entry.toolID] = entries
        persist(entries, for: entry.toolID)
        return entry
    }

    public func remove(_ entry: HistoryEntry) {
        var entries = entries(for: entry.toolID)
        entries.removeAll { $0.id == entry.id }
        cache[entry.toolID] = entries
        persist(entries, for: entry.toolID)
    }

    public func clear(toolID: ToolIdentifier) {
        cache[toolID] = []
        persist([], for: toolID)
    }

    /// Vergisst alles — auf der Platte und im Speicher.
    ///
    /// Beides gehört zusammen: Wer nur die Dateien löscht, hat den Verlauf
    /// noch im Fenster stehen, bis die App neu startet — und wer nur den
    /// Zwischenspeicher leert, sieht ihn beim nächsten Start wieder.
    public func forgetEverything() {
        cache = [:]
        let manager = FileManager.default
        let contents = (try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in contents where url.pathExtension == "json" {
            try? manager.removeItem(at: url)
        }
    }

    // MARK: - Disk

    private func url(for toolID: ToolIdentifier) -> URL {
        let safe = toolID.rawValue.replacingOccurrences(of: "/", with: "_")
        return directory.appending(path: "\(safe).json")
    }

    private func load(_ toolID: ToolIdentifier) -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url(for: toolID)) else { return [] }
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func persist(_ entries: [HistoryEntry], for toolID: ToolIdentifier) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(entries)
            try data.write(to: url(for: toolID), options: .atomic)
        } catch {
            // History is a convenience, never load-bearing: a failed write must
            // not take down the tool the user is in the middle of using.
            NSLog("[Anvil] history write failed for \(toolID): \(error.localizedDescription)")
        }
    }
}
