import AnvilKit
import Foundation

/// Wo der Platz auf der Platte hingeht.
public struct DiskUsage: Sendable, Hashable {
    /// Ein Ordner oder eine Datei mit ihrem Anteil.
    public struct Node: Sendable, Hashable, Identifiable {
        public let name: String
        public let path: String
        public let bytes: Int
        public let fileCount: Int
        public let isDirectory: Bool

        public init(
            name: String,
            path: String,
            bytes: Int,
            fileCount: Int,
            isDirectory: Bool
        ) {
            self.name = name
            self.path = path
            self.bytes = bytes
            self.fileCount = fileCount
            self.isDirectory = isDirectory
        }

        public var id: String { path }

        /// Der Anteil am Ganzen, zwischen 0 und 1.
        public func share(of total: Int) -> Double {
            guard total > 0 else { return 0 }
            return Double(bytes) / Double(total)
        }
    }

    public let root: URL
    public let children: [Node]
    public let files: [Node]
    public let total: Int
    public let fileCount: Int

    public init(root: URL, children: [Node], files: [Node], total: Int, fileCount: Int) {
        self.root = root
        self.children = children
        self.files = files
        self.total = total
        self.fileCount = fileCount
    }

    public static let empty = DiskUsage(
        root: URL(fileURLWithPath: "/"),
        children: [],
        files: [],
        total: 0,
        fileCount: 0
    )

    public var isEmpty: Bool { children.isEmpty && fileCount == 0 }

    // MARK: - Rechnen

    /// Fasst eine Liste von Dateien zu den Ordnern direkt unter `root`
    /// zusammen.
    public static func make(root: URL, files: [(url: URL, size: Int)]) -> DiskUsage {
        var folders: [String: (bytes: Int, count: Int)] = [:]
        var loose: [Node] = []
        var all: [Node] = []
        var total = 0

        for file in files {
            total += file.size
            let relative = FileWalk.relativePath(of: file.url, under: root)
            let parts = relative.components(separatedBy: "/").filter { !$0.isEmpty }

            let node = Node(
                name: file.url.lastPathComponent,
                path: file.url.path,
                bytes: file.size,
                fileCount: 1,
                isDirectory: false
            )
            all.append(node)

            guard parts.count > 1, let first = parts.first else {
                loose.append(node)
                continue
            }

            let current = folders[first] ?? (bytes: 0, count: 0)
            folders[first] = (bytes: current.bytes + file.size, count: current.count + 1)
        }

        let folderNodes = folders.map { name, sum in
            Node(
                name: name,
                path: root.appending(path: name).path,
                bytes: sum.bytes,
                fileCount: sum.count,
                isDirectory: true
            )
        }

        return DiskUsage(
            root: root,
            children: (folderNodes + loose).sorted { $0.bytes > $1.bytes },
            files: all.sorted { $0.bytes > $1.bytes },
            total: total,
            fileCount: files.count
        )
    }

    /// Die größten Dateien, egal wie tief sie liegen.
    public func largestFiles(_ limit: Int = 20) -> [Node] {
        Array(files.prefix(limit))
    }

    /// Wie viel Platz auf welche Endung geht.
    public func byExtension(_ limit: Int = 10) -> [Node] {
        var sums: [String: (bytes: Int, count: Int)] = [:]
        for file in files {
            let name = URL(fileURLWithPath: file.name).pathExtension.lowercased()
            let key = name.isEmpty ? localized("ohne Endung") : name
            let current = sums[key] ?? (bytes: 0, count: 0)
            sums[key] = (bytes: current.bytes + file.bytes, count: current.count + 1)
        }

        return sums
            .map { key, sum in
                Node(
                    name: key,
                    path: key,
                    bytes: sum.bytes,
                    fileCount: sum.count,
                    isDirectory: false
                )
            }
            .sorted { $0.bytes > $1.bytes }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Ausgeben

    public static let reportColumns = [
        localized("Name"),
        localized("Größe"),
        localized("Anteil"),
        localized("Dateien")
    ]

    public func rows(_ nodes: [Node]) -> [[String]] {
        nodes.map { node in
            [
                node.isDirectory ? node.name + "/" : node.name,
                StoredData.size(node.bytes),
                Self.percent(node.share(of: total)),
                "\(node.fileCount)"
            ]
        }
    }

    /// Ein Anteil als Prozentzahl, ohne Nachkommastellen.
    public static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded())) %"
    }

    public var report: String {
        let header = Self.reportColumns.joined(separator: "\t")
        return ([header] + rows(children).map { $0.joined(separator: "\t") })
            .joined(separator: "\n")
    }
}
