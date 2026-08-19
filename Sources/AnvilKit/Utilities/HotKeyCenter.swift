import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

/// Registers key combinations that fire while any app is frontmost.
@MainActor
@Observable
public final class HotKeyCenter {
    public static let shared = HotKeyCenter()

    /// Registrations by owner name, so a second `register` for the same owner
    /// replaces the first instead of stacking up.
    @ObservationIgnored private var registrations: [String: Registration] = [:]
    @ObservationIgnored private var handlers: [UInt32: () -> Void] = [:]
    @ObservationIgnored private var eventHandler: EventHandlerRef?
    @ObservationIgnored private var nextIdentifier: UInt32 = 1

    /// The shortcuts currently held, for showing conflicts in Settings.
    public private(set) var activeShortcuts: [String: GlobalShortcut] = [:]

    private struct Registration {
        let identifier: UInt32
        let reference: EventHotKeyRef
        let shortcut: GlobalShortcut
    }

    /// Four-character signature Carbon uses to namespace hot keys.
    private static let signature: OSType = {
        let characters = Array("ANVL".utf8)
        return characters.reduce(OSType(0)) { ($0 << 8) + OSType($1) }
    }()

    private init() {}

    // MARK: - Registration

    /// Claims `shortcut` for `owner`.
    public func register(
        _ shortcut: GlobalShortcut,
        owner: String,
        handler: @escaping () -> Void
    ) throws {
        unregister(owner: owner)
        try installEventHandlerIfNeeded()

        let identifier = nextIdentifier
        nextIdentifier += 1

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        var reference: EventHotKeyRef?

        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            throw AnvilError.unexpected(
                localized("Die Tastenkombination \(shortcut.displayString) ist schon von einer anderen App belegt.")
            )
        }

        registrations[owner] = Registration(
            identifier: identifier,
            reference: reference,
            shortcut: shortcut
        )
        handlers[identifier] = handler
        activeShortcuts[owner] = shortcut
    }

    public func unregister(owner: String) {
        guard let registration = registrations.removeValue(forKey: owner) else { return }
        UnregisterEventHotKey(registration.reference)
        handlers.removeValue(forKey: registration.identifier)
        activeShortcuts.removeValue(forKey: owner)
    }

    public func unregisterAll() {
        for owner in registrations.keys { unregister(owner: owner) }
    }

    public func shortcut(for owner: String) -> GlobalShortcut? {
        activeShortcuts[owner]
    }

    // MARK: - Dispatch

    /// Called from the Carbon callback below.
    fileprivate func fire(identifier: UInt32) {
        handlers[identifier]?()
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            anvilHotKeyHandler,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        guard status == noErr else {
            throw AnvilError.unexpected(
                localized("Globale Tastenkürzel konnten nicht eingerichtet werden.")
            )
        }
    }
}

/// The C callback Carbon calls on the main run loop.
private let anvilHotKeyHandler: EventHandlerUPP = { _, event, _ in
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let identifier = hotKeyID.id
    Task { @MainActor in
        HotKeyCenter.shared.fire(identifier: identifier)
    }
    return noErr
}
