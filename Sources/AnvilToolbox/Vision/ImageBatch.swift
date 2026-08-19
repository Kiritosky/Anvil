import AnvilKit
import AppKit
import Foundation
import Observation

/// Der Stapel, an dem das Bildwerkzeug gerade arbeitet.
@MainActor
@Observable
public final class ImageBatch {
    /// Eine Datei im Stapel, mit dem, was aus ihr wurde.
    public struct Entry: Identifiable, Sendable {
        public let id = UUID()
        public let url: URL
        public let originalBytes: Int
        public var output: ImageConversion.Output?
        public var failure: String?

        public var name: String { url.deletingPathExtension().lastPathComponent }

        /// Wie viel kleiner es wurde. Negativ heißt größer — das kommt vor und
        /// wird nicht versteckt.
        public var savedBytes: Int {
            guard let output else { return 0 }
            return originalBytes - output.byteCount
        }
    }

    public private(set) var entries: [Entry] = []
    public private(set) var isWorking = false
    /// Wie viele von wie vielen — für den Balken.
    public private(set) var progress: Double?

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }
    public var successCount: Int { entries.filter { $0.output != nil }.count }
    public var failureCount: Int { entries.filter { $0.failure != nil }.count }

    public var totalOriginalBytes: Int { entries.reduce(0) { $0 + $1.originalBytes } }
    public var totalOutputBytes: Int { entries.reduce(0) { $0 + ($1.output?.byteCount ?? 0) } }

    // MARK: - Befüllen

    public func load(_ urls: [URL]) {
        let known = Set(entries.map(\.url))
        let fresh = urls.filter { !known.contains($0) }

        entries += fresh.map { url in
            Entry(url: url, originalBytes: byteCount(of: url))
        }
    }

    public func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
    }

    public func clear() {
        entries = []
        progress = nil
    }

    // MARK: - Rechnen

    /// Rechnet den ganzen Stapel durch.
    public func convert(
        to format: ImageConversion.Format,
        scale: ImageConversion.Scale,
        longestEdge: Int,
        quality: Double
    ) async {
        guard !entries.isEmpty, !isWorking else { return }
        isWorking = true
        progress = 0
        defer {
            isWorking = false
            progress = nil
        }

        let urls = entries.map(\.url)

        for start in stride(from: 0, to: urls.count, by: Self.batchSize) {
            let end = min(start + Self.batchSize, urls.count)
            let slice = Array(urls[start..<end])

            let results = await Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: ImageConversion.BatchResult?.self) { group in
                    for url in slice {
                        group.addTask {
                            ImageConversion.convertAll(
                                [url],
                                to: format,
                                scale: scale,
                                longestEdge: longestEdge,
                                quality: quality
                            ).first
                        }
                    }

                    var collected: [ImageConversion.BatchResult] = []
                    for await result in group {
                        if let result { collected.append(result) }
                    }
                    return collected
                }
            }.value

            progress = Double(end) / Double(urls.count)

            for outcome in results {
                guard let position = entries.firstIndex(where: { $0.url == outcome.url }) else {
                    continue
                }
                entries[position].output = outcome.output
                entries[position].failure = outcome.failure
            }
        }
    }

    /// Wie viele Bilder gleichzeitig gerechnet werden.
    static let batchSize = 4

    // MARK: - Sichern

    /// Schreibt alles, was geklappt hat, in einen Ordner.
    @discardableResult
    public func write(into directory: URL) throws -> Int {
        var written = 0
        var firstFailure: (any Error)?

        for entry in entries {
            guard let output = entry.output else { continue }
            let url = ExportFile.uniqueURL(
                in: directory,
                named: entry.name,
                extension: output.format.pathExtension
            )
            do {
                try output.data.write(to: url)
                written += 1
            } catch {
                firstFailure = firstFailure ?? error
            }
        }

        if written == 0, let firstFailure {
            throw AnvilError.storage(
                localized("Nichts konnte gesichert werden: \(firstFailure.localizedDescription)")
            )
        }
        return written
    }

    private func byteCount(of url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }
}
