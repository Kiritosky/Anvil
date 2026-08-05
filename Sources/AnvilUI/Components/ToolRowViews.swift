import AnvilKit
import SwiftUI

/// A tool in a list: sidebar, command palette, search results.
///
/// One row definition for all three places means a tool looks identical
/// wherever it shows up, and the palette never drifts from the sidebar.
public struct ToolListRow: View {
    private let metadata: ToolMetadata
    private let isSelected: Bool
    private let isFavourite: Bool
    private let showsSubtitle: Bool
    private let onToggleFavourite: (() -> Void)?

    @State private var isHovering = false

    public init(
        metadata: ToolMetadata,
        isSelected: Bool = false,
        isFavourite: Bool = false,
        showsSubtitle: Bool = true,
        onToggleFavourite: (() -> Void)? = nil
    ) {
        self.metadata = metadata
        self.isSelected = isSelected
        self.isFavourite = isFavourite
        self.showsSubtitle = showsSubtitle
        self.onToggleFavourite = onToggleFavourite
    }

    public var body: some View {
        HStack(spacing: AnvilSpacing.sm) {
            ToolIconBadge(
                systemImage: metadata.systemImage,
                tone: metadata.usesAI ? .ai : .accent,
                size: AnvilSize.toolIcon
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: AnvilSpacing.xs) {
                    Text(metadata.title)
                        .font(AnvilFont.rowTitle)
                        .foregroundStyle(AnvilColor.textPrimary)
                        .lineLimit(1)

                    if let badge = metadata.badge {
                        // Das Abzeichen kommt aus den Metadaten und ist dort
                        // schon übersetzt worden.
                        StatusPill(.resolved(badge), tone: .accent)
                    }
                }

                if showsSubtitle, !metadata.subtitle.isEmpty {
                    Text(metadata.subtitle)
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AnvilSpacing.xs)

            if let onToggleFavourite, isHovering || isFavourite {
                Button(action: onToggleFavourite) {
                    Image(systemName: isFavourite ? "star.fill" : "star")
                }
                .buttonStyle(AnvilIconButtonStyle(tone: isFavourite ? .warning : .neutral))
                .help(isFavourite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen")
            }
        }
        .padding(.horizontal, AnvilSpacing.sm)
        .padding(.vertical, AnvilSpacing.xs + 1)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                .fill(isSelected ? AnvilColor.selection : (isHovering ? AnvilColor.hover : .clear))
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(AnvilMotion.quick, value: isHovering)
    }
}

/// A tool as a tappable card, for the start screen.
public struct ToolCard: View {
    private let metadata: ToolMetadata
    private let action: () -> Void

    @State private var isHovering = false

    public init(metadata: ToolMetadata, action: @escaping () -> Void) {
        self.metadata = metadata
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AnvilSpacing.sm) {
                HStack(spacing: AnvilSpacing.sm) {
                    ToolIconBadge(
                        systemImage: metadata.systemImage,
                        tone: metadata.usesAI ? .ai : .accent,
                        size: 28
                    )
                    Spacer(minLength: 0)
                    if metadata.usesAI {
                        StatusPill("KI", systemImage: "sparkles", tone: .ai)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(metadata.title)
                        .font(AnvilFont.body.weight(.semibold))
                        .foregroundStyle(AnvilColor.textPrimary)
                        .lineLimit(1)
                    Text(metadata.subtitle)
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AnvilSpacing.md)
            .frame(height: 116, alignment: .top)
            .background {
                RoundedRectangle(cornerRadius: AnvilRadius.lg, style: .continuous)
                    .fill(isHovering ? AnvilColor.field : AnvilColor.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AnvilRadius.lg, style: .continuous)
                    .strokeBorder(
                        isHovering ? AnvilColor.accent.opacity(0.4) : AnvilColor.border,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(AnvilMotion.quick, value: isHovering)
    }
}
