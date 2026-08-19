import Foundation

/// Identifies one thing a key combination can trigger.
public struct ShortcutActionID: Hashable, Sendable, Codable, RawRepresentable,
                                ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }
}

/// Where a shortcut is listened for.
public enum ShortcutScope: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Registered, but not listened for.
    case off
    /// Works while Anvil is the frontmost app. Appears in the menu bar.
    case app
    /// Works from any app, via the system hot-key API.
    case global

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: localized("Aus")
        case .app: localized("Nur in Anvil")
        case .global: localized("Überall")
        }
    }

    public var explanation: String {
        switch self {
        case .off:
            localized("Das Kürzel ist eingetragen, aber nichts hört darauf.")
        case .app:
            localized("Gilt, während Anvil vorne ist, und steht im Menü.")
        case .global:
            localized("Gilt in jeder App. Kann mit anderen Programmen kollidieren.")
        }
    }

    public var systemImage: String {
        switch self {
        case .off: "circle.slash"
        case .app: "macwindow"
        case .global: "globe"
        }
    }
}

/// What the user chose for one action.
public struct ShortcutSetting: Codable, Sendable, Hashable {
    public var shortcut: GlobalShortcut?
    public var scope: ShortcutScope

    public init(shortcut: GlobalShortcut?, scope: ShortcutScope) {
        self.shortcut = shortcut
        self.scope = scope
    }
}

/// Something that can be triggered by a key combination.
@MainActor
public struct ShortcutAction: Identifiable, Sendable {
    public let id: ShortcutActionID
    public let title: String
    public let subtitle: String
    public let systemImage: String
    /// Groups the action under its tool in settings. `nil` for app-wide ones.
    public let toolID: ToolIdentifier?
    public let defaultShortcut: GlobalShortcut?
    public let defaultScope: ShortcutScope
    public let handler: @MainActor () -> Void

    public init(
        id: ShortcutActionID,
        title: String,
        subtitle: String = "",
        systemImage: String,
        toolID: ToolIdentifier? = nil,
        defaultShortcut: GlobalShortcut? = nil,
        defaultScope: ShortcutScope = .off,
        handler: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = localized(runtime: title)
        self.subtitle = localized(runtime: subtitle)
        self.systemImage = systemImage
        self.toolID = toolID
        self.defaultShortcut = defaultShortcut
        self.defaultScope = defaultScope
        self.handler = handler
    }

    public var defaultSetting: ShortcutSetting {
        ShortcutSetting(shortcut: defaultShortcut, scope: defaultScope)
    }
}
