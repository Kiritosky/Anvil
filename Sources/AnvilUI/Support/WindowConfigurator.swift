import AppKit
import SwiftUI

/// Remembers where a window was and how big.
///
/// SwiftUI restores a window's frame only when the system's "reopen windows"
/// setting happens to be on. For a tool you open twenty times a day that is
/// not good enough — so the frame is saved under a name of our own, which
/// AppKit has done reliably since long before SwiftUI existed.
public struct WindowConfigurator: NSViewRepresentable {
    private let autosaveName: String
    private let minimumSize: NSSize

    public init(autosaveName: String, minimumSize: NSSize = NSSize(width: 900, height: 600)) {
        self.autosaveName = autosaveName
        self.minimumSize = minimumSize
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The window does not exist while the view is being made; one turn
        // later it does.
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    public func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window, window.frameAutosaveName != autosaveName else { return }
        window.minSize = minimumSize
        // Returns false when there was nothing saved yet, which is fine: the
        // first launch keeps whatever size SwiftUI asked for.
        _ = window.setFrameAutosaveName(autosaveName)
    }
}

extension View {
    /// Saves and restores this window's position and size.
    public func anvilWindowFrame(
        autosaveName: String,
        minimumSize: NSSize = NSSize(width: 900, height: 600)
    ) -> some View {
        background(WindowConfigurator(autosaveName: autosaveName, minimumSize: minimumSize))
    }
}
