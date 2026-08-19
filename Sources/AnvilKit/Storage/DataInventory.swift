import Foundation

/// Was Anvil auf der Platte liegen hat — und wie man es wieder los wird.
public struct StoredData: Sendable, Identifiable, Hashable {
    /// Eine Ablage — je Ordner eine.
    public enum Kind: String, Sendable, Hashable, CaseIterable, Identifiable {
        case history
        case drafts
        case recordings
        case screenshots
        case exports
        case customTools

        public var id: String { rawValue }

        public var url: URL {
            switch self {
            case .history: AppPaths.history
            case .drafts: AppPaths.drafts
            case .recordings: AppPaths.recordings
            case .screenshots: AppPaths.screenshots
            case .exports: AppPaths.exports
            case .customTools: AppPaths.customTools
            }
        }

        public var title: String {
            switch self {
            case .history: localized("Verlauf")
            case .drafts: localized("Gemerkte Eingaben")
            case .recordings: localized("Aufnahmen")
            case .screenshots: localized("Bildschirmfotos")
            case .exports: localized("Exporte")
            case .customTools: localized("Eigene Werkzeuge")
            }
        }

        public var explanation: String {
            switch self {
            case .history: localized("Abgeschlossene Durchläufe der Diktat- und KI-Werkzeuge.")
            case .drafts: localized("Was zuletzt in einem Werkzeug stand.")
            case .recordings: localized("Aufgenommenes Audio, sofern behalten.")
            case .screenshots: localized("Aufnahmen vom Bildschirm, sofern behalten.")
            case .exports: localized("Was du selbst aus einem Werkzeug herausgeschrieben hast.")
            case .customTools: localized("Deine eigenen Werkzeuge als JSON-Dateien.")
            }
        }

        public var systemImage: String {
            switch self {
            case .history: "clock.arrow.circlepath"
            case .drafts: "square.and.pencil"
            case .recordings: "waveform"
            case .screenshots: "camera"
            case .exports: "square.and.arrow.up"
            case .customTools: "wrench.and.screwdriver"
            }
        }

        /// Ob „alles löschen" das hier mitnimmt.
        public var isRemovedWithEverything: Bool { self != .customTools }
    }

    public let kind: Kind
    public let byteCount: Int
    public let fileCount: Int

    public var id: String { kind.rawValue }
    public var isEmpty: Bool { fileCount == 0 }

    public init(kind: Kind, byteCount: Int, fileCount: Int) {
        self.kind = kind
        self.byteCount = byteCount
        self.fileCount = fileCount
    }

    /// „12 Dateien · 3,4 MB" — oder, wenn nichts da ist, dass nichts da ist.
    public var summary: String {
        guard fileCount > 0 else { return localized("leer") }
        let size = Self.size(byteCount)
        return localized("\(fileCount) Dateien · \(size)")
    }

    public static func size(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// Sieht nach, was da ist, und räumt es weg.
public enum DataInventory {
    /// Was in jeder Ablage liegt.
    public static func scan(_ kinds: [StoredData.Kind] = StoredData.Kind.allCases) -> [StoredData] {
        kinds.map { kind in
            let counted = count(in: kind.url)
            return StoredData(kind: kind, byteCount: counted.bytes, fileCount: counted.files)
        }
    }

    /// Zählt Dateien und Bytes in einem Ordner, samt Unterordnern.
    static func count(in folder: URL) -> (files: Int, bytes: Int) {
        let manager = FileManager.default
        guard let walker = manager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else { return (0, 0) }

        var files = 0
        var bytes = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            files += 1
            bytes += values?.fileSize ?? 0
        }
        return (files, bytes)
    }

    /// Leert eine Ablage — den Ordner selbst lässt es stehen.
    public static func empty(_ kind: StoredData.Kind) throws {
        try empty(at: kind.url)
    }

    static func empty(at folder: URL) throws {
        let manager = FileManager.default
        let contents = (try? manager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []

        for url in contents {
            try manager.removeItem(at: url)
        }
    }

    /// Leert alles, was zur Ablage gehört — die eigenen Werkzeuge bleiben.
    public static func emptyEverything() throws {
        for kind in StoredData.Kind.allCases where kind.isRemovedWithEverything {
            try empty(kind)
        }
    }

    /// Wie viel insgesamt zusammengekommen ist.
    public static func totalBytes(_ items: [StoredData]) -> Int {
        items.reduce(0) { $0 + $1.byteCount }
    }
}
