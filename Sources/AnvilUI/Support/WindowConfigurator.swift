import AppKit
import SwiftUI

/// Remembers where a window was and how big.
public struct WindowConfigurator: NSViewRepresentable {
    private let autosaveName: String
    private let minimumSize: NSSize

    public init(autosaveName: String, minimumSize: NSSize = NSSize(width: 900, height: 600)) {
        self.autosaveName = autosaveName
        self.minimumSize = minimumSize
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    public func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window, window.frameAutosaveName != autosaveName else { return }
        window.minSize = minimumSize
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
