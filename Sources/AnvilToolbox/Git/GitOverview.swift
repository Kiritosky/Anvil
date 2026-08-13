import AnvilKit
import Foundation

/// Ein Repository mit allem, was darüber bekannt ist.
public struct GitRepository: Sendable, Hashable, Identifiable {
    public let url: URL
    public let status: GitStatus
    public let branches: [GitBranch]
    /// Wann hier zuletzt etwas passiert ist.
    public let lastCommit: GitCommit?
    /// Was `git` gesagt hat, falls es nicht funktioniert hat.
    public let failure: String?

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }

    public init(
        url: URL,
        status: GitStatus,
        branches: [GitBranch] = [],
        lastCommit: GitCommit? = nil,
        failure: String? = nil
    ) {
        self.url = url
        self.status = status
        self.branches = branches
        self.lastCommit = lastCommit
        self.failure = failure
    }

    public var staleBranches: [GitBranch] { branches.filter(\.isStale) }

    /// Ob dieses Repository Aufmerksamkeit braucht.
    public var needsAttention: Bool {
        failure != nil || status.hasUnsavedWork || !staleBranches.isEmpty
    }
}

/// Viele Repositories auf einmal.
///
/// Der Grund, warum das ein eigener Typ ist: Die Frage, die man wirklich hat,
/// lautet nie „wie steht es um dieses Repository", sondern „wo liegt noch etwas
/// herum". Die erste beantwortet jede Entwicklungsumgebung, die zweite keine —
/// dafür müsste man dreißig Ordner einzeln aufmachen.
public struct GitOverview: Sendable {
    public let repositories: [GitRepository]

    public init(_ repositories: [GitRepository]) {
        self.repositories = repositories
    }

    public static let empty = GitOverview([])

    public var isEmpty: Bool { repositories.isEmpty }
    public var count: Int { repositories.count }

    public var needingAttention: [GitRepository] { repositories.filter(\.needsAttention) }
    public var dirty: [GitRepository] { repositories.filter { !$0.status.isClean } }
    public var ahead: [GitRepository] { repositories.filter { $0.status.ahead > 0 } }
    public var behind: [GitRepository] { repositories.filter { $0.status.behind > 0 } }
    public var failed: [GitRepository] { repositories.filter { $0.failure != nil } }
    public var staleBranchCount: Int {
        repositories.reduce(0) { $0 + $1.staleBranches.count }
    }

    /// Wonach die Liste gefiltert wird.
    public enum Filter: String, Sendable, Hashable, CaseIterable, Identifiable {
        case all
        case attention
        case dirty
        case ahead
        case behind

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .all: localized("Alle")
            case .attention: localized("Auffällig")
            case .dirty: localized("Geändert")
            case .ahead: localized("Nicht gepusht")
            case .behind: localized("Hinterher")
            }
        }

        public var systemImage: String {
            switch self {
            case .all: "square.grid.2x2"
            case .attention: "exclamationmark.circle"
            case .dirty: "pencil"
            case .ahead: "arrow.up"
            case .behind: "arrow.down"
            }
        }
    }

    public func filtered(_ filter: Filter) -> [GitRepository] {
        switch filter {
        case .all: repositories
        case .attention: needingAttention
        case .dirty: dirty
        case .ahead: ahead
        case .behind: behind
        }
    }

    // MARK: - Ausgeben

    public static let reportColumns = [
        localized("Repository"),
        localized("Zweig"),
        localized("Letzter Commit"),
        localized("Voraus"),
        localized("Zurück"),
        localized("Geändert"),
        localized("Alte Zweige")
    ]

    public static func row(_ repository: GitRepository) -> [String] {
        let status = repository.status
        return [
            repository.name,
            status.branch ?? localized("abgelöst"),
            repository.lastCommit?.ageText() ?? "—",
            "\(status.ahead)",
            "\(status.behind)",
            "\(status.changes.count)",
            "\(repository.staleBranches.count)"
        ]
    }

    /// Eine Zeile je Repository, tabulatorgetrennt — das, was man in ein
    /// Ticket oder eine Nachricht klebt.
    public func report(_ filter: Filter = .all) -> String {
        let header = Self.reportColumns.joined(separator: "\t")
        let rows = filtered(filter).map { Self.row($0).joined(separator: "\t") }
        return ([header] + rows).joined(separator: "\n")
    }

    /// Die Befehle, mit denen sich die alten Zweige entfernen ließen — eine
    /// Zeile je Repository, zum Einfügen ins Terminal.
    ///
    /// Anvil führt sie nicht aus, und das ist keine Bequemlichkeit: Ein
    /// Werkzeug, das ungefragt Zweige löscht, müsste sich seiner Sache
    /// sicherer sein, als es sein kann. `git branch -d` ist dabei die zweite
    /// Sicherung — im Gegensatz zu `-D` weigert es sich, einen Zweig zu
    /// löschen, dessen Commits nirgendwo sonst stehen.
    public func cleanupCommands(_ filter: Filter = .all) -> String {
        filtered(filter).compactMap { repository -> String? in
            let names = repository.staleBranches.map(\.name)
            guard !names.isEmpty else { return nil }
            let branches = names.map(Shell.quoted).joined(separator: " ")
            return "cd \(Shell.quoted(repository.url.path)) && git branch -d \(branches)"
        }
        .joined(separator: "\n")
    }
}
