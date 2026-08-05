import Foundation
import Observation

/// Which tools the user has switched on.
///
/// Stored as the set of *disabled* identifiers, not enabled ones. That way a
/// tool added in a later version shows up automatically instead of staying
/// invisible because it was missing from an allow-list written before it
/// existed.
@MainActor
@Observable
public final class ToolActivationStore {
    @ObservationIgnored private let settings: SettingsStore

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    // MARK: - Tools

    public var disabledToolIdentifiers: Set<ToolIdentifier> {
        Set(settings[.disabledTools].map(ToolIdentifier.init(rawValue:)))
    }

    /// Essential tools are always on, whatever is stored.
    public func isEnabled(_ id: ToolIdentifier, isEssential: Bool = false) -> Bool {
        isEssential || !disabledToolIdentifiers.contains(id)
    }

    public func setEnabled(_ enabled: Bool, for id: ToolIdentifier) {
        var disabled = settings[.disabledTools]
        if enabled {
            disabled.removeAll { $0 == id.rawValue }
        } else if !disabled.contains(id.rawValue) {
            disabled.append(id.rawValue)
        }
        settings[.disabledTools] = disabled
    }

    public func toggle(_ id: ToolIdentifier) {
        setEnabled(!isEnabled(id), for: id)
    }

    // MARK: - Bundles

    public var disabledBundleIdentifiers: Set<String> {
        Set(settings[.disabledToolBundles])
    }

    public func isBundleEnabled(_ origin: ToolOrigin) -> Bool {
        origin.isEssential || !disabledBundleIdentifiers.contains(origin.bundleIdentifier)
    }

    public func setBundleEnabled(_ enabled: Bool, for origin: ToolOrigin) {
        guard !origin.isEssential else { return }
        var disabled = settings[.disabledToolBundles]
        if enabled {
            disabled.removeAll { $0 == origin.bundleIdentifier }
        } else if !disabled.contains(origin.bundleIdentifier) {
            disabled.append(origin.bundleIdentifier)
        }
        settings[.disabledToolBundles] = disabled
    }

    /// A tool is active when both it and the bundle it came from are on.
    public func isActive(_ registration: ToolRegistration) -> Bool {
        guard isBundleEnabled(registration.origin) else { return false }
        return isEnabled(registration.id, isEssential: registration.origin.isEssential)
    }

    /// Switches everything back on.
    public func reset() {
        settings[.disabledTools] = []
        settings[.disabledToolBundles] = []
    }

    public var hasDisabledAnything: Bool {
        !settings[.disabledTools].isEmpty || !settings[.disabledToolBundles].isEmpty
    }
}

extension SettingKey {
    public static var disabledTools: SettingKey<[String]> {
        SettingKey<[String]>("disabledTools", default: [])
    }

    public static var disabledToolBundles: SettingKey<[String]> {
        SettingKey<[String]>("disabledToolBundles", default: [])
    }
}
