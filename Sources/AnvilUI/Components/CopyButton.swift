import AppKit
import SwiftUI

/// Copies text and confirms it in place.
public struct CopyButton: View {
    private let text: () -> String
    private let label: LocalizedStringKey?
    private let onCopy: ((String) -> Void)?

    @State private var didCopy = false
    @State private var revertTask: Task<Void, Never>?

    /// Icon-only variant for pane headers.
    public init(text: @autoclosure @escaping () -> String, onCopy: ((String) -> Void)? = nil) {
        self.text = text
        self.label = nil
        self.onCopy = onCopy
    }

    /// Labelled variant for action rows.
    public init(
        _ label: LocalizedStringKey,
        text: @autoclosure @escaping () -> String,
        onCopy: ((String) -> Void)? = nil
    ) {
        self.text = text
        self.label = label
        self.onCopy = onCopy
    }

    public var body: some View {
        Group {
            if let label {
                AnvilButton(
                    didCopy ? "Kopiert" : label,
                    systemImage: didCopy ? "checkmark" : "doc.on.doc",
                    role: .secondary,
                    action: copy
                )
            } else {
                Button(action: copy) {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(AnvilIconButtonStyle(tone: didCopy ? .success : .neutral))
                .anvilHelp("In die Zwischenablage kopieren")
            }
        }
        .disabled(text().isEmpty)
        .animation(AnvilMotion.quick, value: didCopy)
        .onDisappear { revertTask?.cancel() }
    }

    private func copy() {
        let value = text()
        guard !value.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        onCopy?(value)

        didCopy = true
        revertTask?.cancel()
        revertTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }
}
