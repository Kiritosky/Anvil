import AnvilKit
import AnvilUI
import SwiftUI

/// ⌘K: type a few letters, hit return, land in a tool.
struct CommandPalette: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFieldFocused: Bool

    private var results: [ToolMetadata] {
        environment.registry.search(query, limit: 12)
    }

    var body: some View {
        VStack(spacing: 0) {
            field
            Divider()
            resultList
        }
        .frame(width: AnvilSize.paletteWidth)
        .background(AnvilColor.canvas)
        .onAppear { isFieldFocused = true }
    }

    private var field: some View {
        HStack(spacing: AnvilSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AnvilColor.textTertiary)

            TextField("Tool öffnen …", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isFieldFocused)
                .onSubmit(openHighlighted)
                .onChange(of: query) { _, _ in highlighted = 0 }

            Text("esc")
                .font(AnvilFont.caption)
                .foregroundStyle(AnvilColor.textTertiary)
                .padding(.horizontal, AnvilSpacing.xs)
                .padding(.vertical, 1)
                .background {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AnvilColor.hover)
                }
        }
        .padding(.horizontal, AnvilSpacing.lg)
        .frame(height: 52)
    }

    @ViewBuilder
    private var resultList: some View {
        if results.isEmpty {
            EmptyStateView(
                title: "Nichts gefunden",
                message: "Kein Tool passt zu „\(query)\".",
                systemImage: "magnifyingglass"
            )
            .frame(height: 180)
        } else {
            ScrollView {
                let shortcuts = environment.registry.quickAccessShortcuts
                LazyVStack(spacing: AnvilSpacing.xxs) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, tool in
                        Button { environment.open(tool.id); dismiss() } label: {
                            ToolListRow(
                                metadata: tool,
                                isSelected: index == highlighted,
                                shortcutHint: shortcuts[tool.id]
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AnvilSpacing.sm)
            }
            .frame(maxHeight: 380)
            .onMoveCommand { direction in
                switch direction {
                case .up: highlighted = max(0, highlighted - 1)
                case .down: highlighted = min(results.count - 1, highlighted + 1)
                default: break
                }
            }
        }
    }

    private func openHighlighted() {
        guard results.indices.contains(highlighted) else { return }
        environment.open(results[highlighted].id)
        dismiss()
    }
}
