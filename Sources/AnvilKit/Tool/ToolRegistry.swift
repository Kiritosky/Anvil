import Foundation
import Observation

/// Tools that came from the same bundle or the same folder.
///
/// A named type rather than a tuple: SwiftUI's `ForEach` needs an
/// `Identifiable` element or a key path, and key paths cannot address tuple
/// members.
public struct ToolGroup: Identifiable {
    public let origin: ToolOrigin
    public let tools: [ToolRegistration]

    public var id: String { origin.bundleIdentifier }

    public init(origin: ToolOrigin, tools: [ToolRegistration]) {
        self.origin = origin
        self.tools = tools
    }
}

/// The single source of truth for which tools exist.
///
/// The registry knows about every registered tool; the shell only ever shows
/// the *active* ones — those the user has not switched off in the Tool Store,
/// from a bundle that is also switched on. The store itself works against
/// ``allTools`` so a disabled tool remains findable and can be switched back on.
@MainActor
@Observable
public final class ToolRegistry {
    public private(set) var allTools: [ToolRegistration] = []
    private var index: [ToolIdentifier: Int] = [:]

    @ObservationIgnored private let settings: SettingsStore
    public let activation: ToolActivationStore

    public init(settings: SettingsStore, activation: ToolActivationStore? = nil) {
        self.settings = settings
        self.activation = activation ?? ToolActivationStore(settings: settings)
    }

    // MARK: - Registration

    /// Registers a tool. A later registration for the same identifier replaces
    /// the earlier one, which lets a user tool override a built-in one.
    public func register(_ registration: ToolRegistration, origin: ToolOrigin? = nil) {
        var stamped = registration
        if let origin { stamped.origin = origin }

        if let existing = index[stamped.id] {
            allTools[existing] = stamped
        } else {
            index[stamped.id] = allTools.count
            allTools.append(stamped)
        }
    }

    public func register(contentsOf registrations: [ToolRegistration], origin: ToolOrigin? = nil) {
        for registration in registrations { register(registration, origin: origin) }
    }

    public func register(bundle: any ToolBundle.Type) {
        register(contentsOf: bundle.makeTools(), origin: bundle.origin)
    }

    /// Replaces every tool that came from a given bundle identifier.
    ///
    /// Used when user-defined tools are reloaded from disk: drop the old set,
    /// register the new one, leave everything else untouched.
    public func replaceTools(
        fromBundle bundleIdentifier: String,
        with registrations: [ToolRegistration]
    ) {
        allTools.removeAll { $0.origin.bundleIdentifier == bundleIdentifier }
        reindex()
        for registration in registrations { register(registration) }
    }

    public func removeTool(id: ToolIdentifier) {
        allTools.removeAll { $0.id == id }
        reindex()
    }

    private func reindex() {
        index = Dictionary(
            uniqueKeysWithValues: allTools.enumerated().map { ($0.element.id, $0.offset) }
        )
    }

    // MARK: - Active set

    /// Tools the user can actually reach right now.
    public var tools: [ToolRegistration] {
        allTools.filter { activation.isActive($0) }
    }

    public var metadata: [ToolMetadata] {
        tools.map(\.metadata)
    }

    public func tool(id: ToolIdentifier) -> ToolRegistration? {
        index[id].map { allTools[$0] }
    }

    public func isActive(_ id: ToolIdentifier) -> Bool {
        tool(id: id).map { activation.isActive($0) } ?? false
    }

    // MARK: - Grouping

    /// Categories that contain at least one active tool, in display order.
    public var categories: [ToolCategory] {
        var seen: Set<String> = []
        var result: [ToolCategory] = []
        for tool in tools where seen.insert(tool.metadata.category.id).inserted {
            result.append(tool.metadata.category)
        }
        return result.sorted {
            $0.sortOrder == $1.sortOrder ? $0.title < $1.title : $0.sortOrder < $1.sortOrder
        }
    }

    public func tools(in category: ToolCategory) -> [ToolMetadata] {
        metadata
            .filter { $0.category == category }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Everything the Tool Store lists: all tools, disabled ones included,
    /// grouped by where they came from.
    public var toolsByOrigin: [ToolGroup] {
        var order: [ToolOrigin] = []
        var grouped: [String: [ToolRegistration]] = [:]

        for tool in allTools {
            if grouped[tool.origin.bundleIdentifier] == nil {
                order.append(tool.origin)
            }
            grouped[tool.origin.bundleIdentifier, default: []].append(tool)
        }

        return order.map { origin in
            let tools = (grouped[origin.bundleIdentifier] ?? []).sorted {
                $0.metadata.title.localizedCaseInsensitiveCompare($1.metadata.title)
                    == .orderedAscending
            }
            return ToolGroup(origin: origin, tools: tools)
        }
    }

    /// Active tools that contribute a settings page, in sidebar order.
    public var toolsWithSettings: [ToolRegistration] {
        tools
            .filter(\.hasSettings)
            .sorted {
                $0.metadata.category.sortOrder == $1.metadata.category.sortOrder
                    ? $0.metadata.title.localizedCaseInsensitiveCompare($1.metadata.title)
                        == .orderedAscending
                    : $0.metadata.category.sortOrder < $1.metadata.category.sortOrder
            }
    }

    // MARK: - Search

    /// Ranked search across titles, subtitles, keywords and identifiers.
    ///
    /// An empty query returns the active set with favourites first, so the
    /// command palette opens with something useful rather than a blank sheet.
    public func search(
        _ query: String,
        limit: Int = 40,
        includeInactive: Bool = false
    ) -> [ToolMetadata] {
        let pool = (includeInactive ? allTools : tools).map(\.metadata)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let favouriteIDs = Set(favourites)

        guard !trimmed.isEmpty else {
            let pinned = pool.filter { favouriteIDs.contains($0.id) }
            let rest = pool.filter { !favouriteIDs.contains($0.id) }
            return Array((pinned + rest).prefix(limit))
        }

        let recentIDs = recents
        let scored: [(ToolMetadata, Int)] = pool.compactMap { meta in
            guard var score = FuzzyMatch.score(query: trimmed, in: meta.searchCorpus) else {
                return nil
            }
            // A hit in the title is worth more than a hit in a keyword.
            if let titleScore = FuzzyMatch.score(query: trimmed, in: meta.title) {
                score += titleScore + 40
            }
            if favouriteIDs.contains(meta.id) { score += 25 }
            if let rank = recentIDs.firstIndex(of: meta.id) { score += max(0, 20 - rank * 4) }
            return (meta, score)
        }

        return scored
            .sorted {
                $0.1 == $1.1
                    ? $0.0.title.localizedCaseInsensitiveCompare($1.0.title) == .orderedAscending
                    : $0.1 > $1.1
            }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: - Favourites

    public var favourites: [ToolIdentifier] {
        settings[.favouriteTools].map(ToolIdentifier.init(rawValue:))
    }

    public func isFavourite(_ id: ToolIdentifier) -> Bool {
        favourites.contains(id)
    }

    public func toggleFavourite(_ id: ToolIdentifier) {
        var current = settings[.favouriteTools]
        if let existing = current.firstIndex(of: id.rawValue) {
            current.remove(at: existing)
        } else {
            current.append(id.rawValue)
        }
        settings[.favouriteTools] = current
    }

    /// Favourites that are currently active, in the order the user pinned them.
    public var favouriteTools: [ToolMetadata] {
        favourites.compactMap { id in
            guard let tool = tool(id: id), activation.isActive(tool) else { return nil }
            return tool.metadata
        }
    }

    // MARK: - Recents

    public var recents: [ToolIdentifier] {
        settings[.recentTools].map(ToolIdentifier.init(rawValue:))
    }

    public var recentTools: [ToolMetadata] {
        recents.compactMap { id in
            guard let tool = tool(id: id), activation.isActive(tool) else { return nil }
            return tool.metadata
        }
    }

    public func markUsed(_ id: ToolIdentifier) {
        var current = settings[.recentTools]
        current.removeAll { $0 == id.rawValue }
        current.insert(id.rawValue, at: 0)
        settings[.recentTools] = Array(current.prefix(8))
    }

    // MARK: - Schnellzugriff

    /// Wie viele Werkzeuge auf einer Zifferntaste liegen können.
    ///
    /// Neun, weil ⌘0 in der App zurück zur Übersicht führt — so wie in einem
    /// Browser die Null die Ausgangsgröße herstellt.
    public static let quickAccessLimit = 9

    /// Die Werkzeuge auf ⌘1…9, in genau dieser Reihenfolge.
    ///
    /// Erst die Favoriten, dann die zuletzt benutzten. Die Favoriten stehen
    /// vorn, weil ihre Reihenfolge der Benutzer selbst bestimmt hat — die
    /// Zuletzt-Liste ordnet sich dagegen bei jeder Benutzung um, und eine
    /// Taste, die gestern etwas anderes geöffnet hat als heute, ist keine
    /// Abkürzung, sondern eine Falle. Wer sich auf ⌘1 verlassen will, macht
    /// das Werkzeug zum Favoriten; bis dahin ist die Belegung ein Angebot.
    public var quickAccessTools: [ToolMetadata] {
        var result: [ToolMetadata] = []
        var seen: Set<ToolIdentifier> = []
        for tool in favouriteTools + recentTools {
            guard result.count < Self.quickAccessLimit else { break }
            guard seen.insert(tool.id).inserted else { continue }
            result.append(tool)
        }
        return result
    }

    /// Welches Werkzeug auf welcher Taste liegt — zum Anschreiben in der
    /// Oberfläche, damit niemand raten muss.
    public var quickAccessShortcuts: [ToolIdentifier: String] {
        var result: [ToolIdentifier: String] = [:]
        for (index, tool) in quickAccessTools.enumerated() {
            result[tool.id] = "⌘\(index + 1)"
        }
        return result
    }
}
