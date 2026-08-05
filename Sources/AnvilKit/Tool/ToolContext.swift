import Foundation

/// The dependency container handed to every tool when its view is built.
///
/// This is the seam that keeps the toolbox extendable. `AnvilKit` registers the
/// services it owns (settings, history, pasteboard); higher layers register
/// theirs (`AIRouter`, speech services) and expose them through small typed
/// extensions, so a tool writes `context.ai` rather than reaching for a global.
///
/// Services are keyed by type. Registering a second service for the same type
/// replaces the first, which is what makes the container useful in tests and
/// previews: swap in a stub router, build the same view.
@MainActor
public final class ToolContext {
    private var services: [ObjectIdentifier: Any] = [:]

    public let settings: SettingsStore
    public let history: HistoryStore
    public let pasteboard: Pasteboard

    /// - Parameter pasteboard: pass a ``RecordingPasteboard`` in tests. The
    ///   default is built here rather than in the parameter list: a default
    ///   argument is evaluated in the *caller's* isolation, and `Pasteboard` is
    ///   main-actor-isolated.
    public init(
        settings: SettingsStore,
        history: HistoryStore,
        pasteboard: Pasteboard? = nil
    ) {
        self.settings = settings
        self.history = history
        self.pasteboard = pasteboard ?? Pasteboard()
    }

    /// Registers `service` under `type`.
    ///
    /// Pass `type` explicitly when registering a concrete instance under a
    /// protocol: `context.register(router, as: (any Summarizing).self)`.
    public func register<Service>(_ service: Service, as type: Service.Type = Service.self) {
        services[ObjectIdentifier(type)] = service
    }

    /// Returns the service registered for `type`, or `nil`.
    public func resolve<Service>(_ type: Service.Type = Service.self) -> Service? {
        services[ObjectIdentifier(type)] as? Service
    }

    /// The tool registry, registered by the app at launch.
    ///
    /// Exposed here so that the Tool Store and the settings window are ordinary
    /// tools rather than special cases wired into the shell.
    public var registry: ToolRegistry { require(ToolRegistry.self) }

    /// Which tools are switched on.
    public var activation: ToolActivationStore { registry.activation }

    /// Returns the service registered for `type`, trapping if it is missing.
    ///
    /// Use this for services the app always installs at launch — a missing one
    /// is a wiring bug, not a runtime condition worth branching on.
    public func require<Service>(_ type: Service.Type = Service.self) -> Service {
        guard let service = resolve(type) else {
            preconditionFailure(
                "ToolContext is missing a service of type \(type). "
                + "Register it in AppEnvironment before building tool views."
            )
        }
        return service
    }
}
