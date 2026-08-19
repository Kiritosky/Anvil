import SwiftUI

/// A wrapping set of selectable chips.
public struct ChipPicker<Option: Hashable>: View {
    @Binding private var selection: Option
    private let options: [Option]
    private let title: (Option) -> String
    private let systemImage: (Option) -> String?
    private let tone: AnvilTone

    public init(
        selection: Binding<Option>,
        options: [Option],
        tone: AnvilTone = .accent,
        title: @escaping (Option) -> String,
        systemImage: @escaping (Option) -> String? = { _ in nil }
    ) {
        self._selection = selection
        self.options = options
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
    }

    public var body: some View {
        FlowLayout(spacing: AnvilSpacing.xs, lineSpacing: AnvilSpacing.xs) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Chip(
                    title: title(option),
                    systemImage: systemImage(option),
                    isSelected: option == selection,
                    tone: tone
                ) {
                    withAnimation(AnvilMotion.quick) { selection = option }
                }
            }
        }
    }
}

/// A single chip. Also usable on its own as a toggle.
public struct Chip: View {
    private let title: String
    private let systemImage: String?
    private let isSelected: Bool
    private let tone: AnvilTone
    private let action: () -> Void

    @State private var isHovering = false

    public init(
        title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        tone: AnvilTone = .accent,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.tone = tone
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: AnvilSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(.resolved(title))
                    .font(AnvilFont.caption.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? tone.color : AnvilColor.textSecondary)
            .padding(.horizontal, AnvilSpacing.sm)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(
                    isSelected ? tone.fill : (isHovering ? AnvilColor.hover : AnvilColor.field)
                )
            }
            .overlay {
                Capsule().strokeBorder(
                    isSelected ? tone.color.opacity(0.45) : AnvilColor.border,
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(AnvilMotion.quick, value: isHovering)
    }
}
