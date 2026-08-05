import SwiftUI

/// A tool as the registry sees it: metadata, a lazy view factory, and an
/// optional settings view.
///
/// Splitting metadata from the view matters. Metadata is cheap and `Sendable`,
/// so search, the sidebar and the Tool Store never touch tool code. The view —
/// and whatever model object it owns — is built the first time it is shown.
public struct ToolRegistration: Identifiable {
    public let metadata: ToolMetadata
    /// Which bundle or file this tool came from. Stamped by the registry.
    public internal(set) var origin: ToolOrigin

    private let build: @MainActor (ToolContext) -> AnyView
    private let buildSettings: (@MainActor (ToolContext) -> AnyView)?

    public var id: ToolIdentifier { metadata.id }

    /// Whether this tool contributes a page to Settings.
    public var hasSettings: Bool { buildSettings != nil }

    public init<Content: View>(
        metadata: ToolMetadata,
        origin: ToolOrigin = .unspecified,
        @ViewBuilder view: @escaping @MainActor (ToolContext) -> Content
    ) {
        self.metadata = metadata
        self.origin = origin
        self.build = { context in AnyView(view(context)) }
        self.buildSettings = nil
    }

    /// A tool with its own settings page.
    ///
    /// The settings view is shown inside the app's Settings window under the
    /// tool's name, so a tool never has to open a window of its own.
    public init<Content: View, Settings: View>(
        metadata: ToolMetadata,
        origin: ToolOrigin = .unspecified,
        @ViewBuilder view: @escaping @MainActor (ToolContext) -> Content,
        @ViewBuilder settings: @escaping @MainActor (ToolContext) -> Settings
    ) {
        self.metadata = metadata
        self.origin = origin
        self.build = { context in AnyView(view(context)) }
        self.buildSettings = { context in AnyView(settings(context)) }
    }

    /// Escape hatch for callers that already have erased views.
    public init(
        metadata: ToolMetadata,
        origin: ToolOrigin = .unspecified,
        erasedView: @escaping @MainActor (ToolContext) -> AnyView,
        erasedSettings: (@MainActor (ToolContext) -> AnyView)? = nil
    ) {
        self.metadata = metadata
        self.origin = origin
        self.build = erasedView
        self.buildSettings = erasedSettings
    }

    @MainActor
    public func makeView(context: ToolContext) -> AnyView {
        build(context)
    }

    @MainActor
    public func makeSettingsView(context: ToolContext) -> AnyView? {
        buildSettings?(context)
    }
}

/// A group of tools shipped together.
///
/// A bundle is the unit of extension: add a type conforming to this protocol,
/// list it in the app's environment, and its tools appear in the sidebar, the
/// command palette, search and the Tool Store with no other change.
public protocol ToolBundle {
    /// Reverse-DNS identifier, used for diagnostics and in the Tool Store.
    static var bundleIdentifier: String { get }
    static var displayName: String { get }
    /// Bundles the app cannot run without cannot be switched off.
    static var isEssential: Bool { get }

    /// Builds the bundle's tools. Called once at launch, on the main actor.
    @MainActor
    static func makeTools() -> [ToolRegistration]
}

extension ToolBundle {
    public static var isEssential: Bool { false }

    /// The origin stamped onto every tool this bundle registers.
    public static var origin: ToolOrigin {
        ToolOrigin(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            isEssential: isEssential
        )
    }
}
