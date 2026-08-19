import Foundation

/// The dependency container handed to every tool when its view is built.
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
    public func register<Service>(_ service: Service, as type: Service.Type = Service.self) {
        services[ObjectIdentifier(type)] = service
    }

    /// Returns the service registered for `type`, or `nil`.
    public func resolve<Service>(_ type: Service.Type = Service.self) -> Service? {
        services[ObjectIdentifier(type)] as? Service
    }

    /// The tool registry, registered by the app at launch.
    public var registry: ToolRegistry { require(ToolRegistry.self) }

    /// Which tools are switched on.
    public var activation: ToolActivationStore { registry.activation }

    /// Returns the service registered for `type`, trapping if it is missing.
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
