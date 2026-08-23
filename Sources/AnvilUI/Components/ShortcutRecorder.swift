import AnvilKit
import AppKit
import SwiftUI

/// A field that captures the next key combination you press.
public struct ShortcutRecorder: View {
    @Binding private var shortcut: GlobalShortcut?
    private let placeholder: LocalizedStringKey

    @State private var isRecording = false
    @State private var isHovering = false

    public init(shortcut: Binding<GlobalShortcut?>, placeholder: LocalizedStringKey = "Klicken und Tasten drücken") {
        self._shortcut = shortcut
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: AnvilSpacing.sm) {
            Button {
                isRecording.toggle()
            } label: {
                content
            }
            .buttonStyle(.plain)

            if shortcut != nil, !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(AnvilColor.textTertiary)
                .anvilHelp("Kürzel entfernen")
            }
        }
        .background {
            if isRecording {
                KeyCaptureView { event in
                    handle(event)
                }
                .frame(width: 0, height: 0)
            }
        }
        .onChange(of: isRecording) { _, recording in
            guard recording else { return }
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private var content: some View {
        HStack(spacing: AnvilSpacing.xs) {
            if isRecording {
                Image(systemName: "record.circle")
                    .foregroundStyle(AnvilColor.danger)
                Text("Tasten drücken …")
                    .foregroundStyle(AnvilColor.textSecondary)
            } else if let shortcut {
                Text(verbatim: shortcut.displayString)
                    .font(AnvilFont.mono)
                    .foregroundStyle(AnvilColor.textPrimary)
            } else {
                Text(placeholder)
                    .foregroundStyle(AnvilColor.textTertiary)
            }
        }
        .font(AnvilFont.body)
        .padding(.horizontal, AnvilSpacing.md)
        .frame(height: AnvilSize.controlHeight)
        .frame(minWidth: 160, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                .fill(isRecording ? AnvilColor.danger.opacity(0.1) : AnvilColor.elevated)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                .strokeBorder(
                    isRecording ? AnvilColor.danger.opacity(0.6)
                        : (isHovering ? AnvilColor.borderFocused : AnvilColor.border),
                    lineWidth: 1
                )
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(AnvilMotion.quick, value: isRecording)
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            isRecording = false
            return
        }

        guard let recorded = GlobalShortcut(event: event) else { return }
        shortcut = recorded
        isRecording = false
    }
}

/// An invisible `NSView` that grabs key events while it exists.
private struct KeyCaptureView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CaptureView()
        view.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CaptureView)?.onKeyDown = onKeyDown
    }

    private final class CaptureView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            onKeyDown?(event)
        }

        /// Intercepts combinations AppKit would otherwise route to a menu item,
        /// which is most of the interesting ones.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            onKeyDown?(event)
            return true
        }

        override func flagsChanged(with event: NSEvent) {
        }
    }
}
