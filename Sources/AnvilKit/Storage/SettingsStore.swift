import Foundation
import Observation

/// A typed, defaulted preference key.
public struct SettingKey<Value: Codable & Sendable>: Sendable {
    public let name: String
    public let defaultValue: Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

/// Observable preferences backed by `UserDefaults`.
@MainActor
@Observable
public final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let prefix: String
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    /// Bumped on every write. Reading it inside `get` is what makes SwiftUI
    /// re-evaluate views when a setting changes.
    private var revision: Int = 0

    public init(defaults: UserDefaults = .standard, prefix: String = "anvil.") {
        self.defaults = defaults
        self.prefix = prefix
    }

    /// An in-memory store, for tests and SwiftUI previews.
    public static func ephemeral() -> SettingsStore {
        let suite = UserDefaults(suiteName: "dev.anvil.Anvil.ephemeral.\(UUID().uuidString)")
        return SettingsStore(defaults: suite ?? .standard)
    }

    public subscript<Value>(key: SettingKey<Value>) -> Value {
        get { value(for: key) }
        set { set(newValue, for: key) }
    }

    public func value<Value>(for key: SettingKey<Value>) -> Value {
        _ = revision  // registers the observation dependency
        guard let data = defaults.data(forKey: prefix + key.name) else {
            return key.defaultValue
        }
        guard let boxed = try? decoder.decode([Value].self, from: data), let first = boxed.first
        else {
            return key.defaultValue
        }
        return first
    }

    public func set<Value>(_ newValue: Value, for key: SettingKey<Value>) {
        if let data = try? encoder.encode([newValue]) {
            defaults.set(data, forKey: prefix + key.name)
        }
        revision &+= 1
    }

    public func reset<Value>(_ key: SettingKey<Value>) {
        defaults.removeObject(forKey: prefix + key.name)
        revision &+= 1
    }

    /// A `Binding`-friendly accessor for SwiftUI controls.
    public func binding<Value>(_ key: SettingKey<Value>) -> SettingsBinding<Value> {
        SettingsBinding(store: self, key: key)
    }
}

/// Small indirection so views can write `settings.binding(.autoCopy).wrapped`
/// without SwiftUI's `Binding` leaking into non-UI code.
@MainActor
public struct SettingsBinding<Value: Codable & Sendable> {
    private let store: SettingsStore
    private let key: SettingKey<Value>

    init(store: SettingsStore, key: SettingKey<Value>) {
        self.store = store
        self.key = key
    }

    public var value: Value {
        get { store[key] }
        nonmutating set { store[key] = newValue }
    }
}

// MARK: - Shell keys

extension SettingKey {
    public static var favouriteTools: SettingKey<[String]> {
        SettingKey<[String]>("favouriteTools", default: [])
    }

    public static var recentTools: SettingKey<[String]> {
        SettingKey<[String]>("recentTools", default: [])
    }

    public static var lastOpenedTool: SettingKey<String> {
        SettingKey<String>("lastOpenedTool", default: "")
    }

    /// Copy a tool's primary output to the clipboard as soon as it is ready.
    public static var autoCopyResults: SettingKey<Bool> {
        SettingKey<Bool>("autoCopyResults", default: false)
    }

    public static var showMenuBarItem: SettingKey<Bool> {
        SettingKey<Bool>("showMenuBarItem", default: true)
    }

    public static var historyLimitPerTool: SettingKey<Int> {
        SettingKey<Int>("historyLimitPerTool", default: 50)
    }
}
