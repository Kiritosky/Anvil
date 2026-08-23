import AnvilKit
import SwiftUI

/// A tool in a list: sidebar, command palette, search results.
///
/// Selected means the accent outright, not a tint — the sidebar is the one
/// place in the app where the current position has to be unmissable.
public struct ToolListRow: View {
    private let metadata: ToolMetadata
    private let isSelected: Bool
    private let isFavourite: Bool
    private let showsSubtitle: Bool
    private let shortcutHint: String?
    private let onToggleFavourite: (() -> Void)?

    @State private var isHovering = false

    public init(
        metadata: ToolMetadata,
        isSelected: Bool = false,
        isFavourite: Bool = false,
        showsSubtitle: Bool = true,
        shortcutHint: String? = nil,
        onToggleFavourite: (() -> Void)? = nil
    ) {
        self.metadata = metadata
        self.isSelected = isSelected
        self.isFavourite = isFavourite
        self.showsSubtitle = showsSubtitle
        self.shortcutHint = shortcutHint
        self.onToggleFavourite = onToggleFavourite
    }

    private var tone: AnvilTone { metadata.usesAI ? .ai : .accent }

    private var titleColor: Color {
        isSelected ? AnvilColor.textOnAccent : AnvilColor.textPrimary
    }

    private var subtitleColor: Color {
        isSelected ? AnvilColor.textOnAccent.opacity(0.75) : AnvilColor.textSecondary
    }

    public var body: some View {
        HStack(spacing: AnvilSpacing.sm) {
            Image(systemName: metadata.systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? AnvilColor.textOnAccent : tone.color)
                .frame(width: AnvilSize.toolIcon, alignment: .center)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: AnvilSpacing.xs) {
                    Text(metadata.title)
                        .font(AnvilFont.rowTitle)
                        .foregroundStyle(titleColor)
                        .lineLimit(1)

                    if let badge = metadata.badge {
                        StatusPill(.resolved(badge), tone: isSelected ? .neutral : .accent)
                    }
                }

                if showsSubtitle, !metadata.subtitle.isEmpty {
                    Text(metadata.subtitle)
                        .font(AnvilFont.caption)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AnvilSpacing.xs)

            if let shortcutHint {
                KeycapLabel(shortcutHint, isMuted: !isSelected)
            }

            if let onToggleFavourite, isHovering || isFavourite {
                Button(action: onToggleFavourite) {
                    Image(systemName: isFavourite ? "star.fill" : "star")
                }
                .buttonStyle(AnvilIconButtonStyle(tone: isFavourite ? .warning : .neutral))
                .anvilHelp(isFavourite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen")
            }
        }
        .padding(.horizontal, AnvilSpacing.sm)
        .padding(.vertical, AnvilSpacing.sm - 1)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                .fill(
                    isSelected
                        ? AnvilColor.selectionStrong
                        : (isHovering ? AnvilColor.hover : .clear)
                )
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(AnvilMotion.quick, value: isHovering)
    }
}

/// A tool as a tappable card, for the start screen.
public struct ToolCard: View {
    private let metadata: ToolMetadata
    private let isFavourite: Bool
    private let shortcutHint: String?
    private let onToggleFavourite: (() -> Void)?
    private let action: () -> Void

    @State private var isHovering = false

    public init(
        metadata: ToolMetadata,
        isFavourite: Bool = false,
        shortcutHint: String? = nil,
        onToggleFavourite: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.metadata = metadata
        self.isFavourite = isFavourite
        self.shortcutHint = shortcutHint
        self.onToggleFavourite = onToggleFavourite
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            card
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if let onToggleFavourite, isHovering || isFavourite {
                Button(action: onToggleFavourite) {
                    Image(systemName: isFavourite ? "star.fill" : "star")
                }
                .buttonStyle(AnvilIconButtonStyle(tone: isFavourite ? .warning : .neutral))
                .anvilHelp(isFavourite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen")
                .padding(AnvilSpacing.sm)
            }
        }
        .onHover { isHovering = $0 }
        .animation(AnvilMotion.quick, value: isHovering)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.sm) {
            HStack(spacing: AnvilSpacing.sm) {
                AnvilIconBadge(
                    metadata.systemImage,
                    tone: metadata.usesAI ? .ai : .accent,
                    size: AnvilSize.iconBadgeLarge
                )
                Spacer(minLength: 0)
                if let shortcutHint {
                    KeycapLabel(shortcutHint)
                }
            }

            VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
                HStack(spacing: AnvilSpacing.xs) {
                    Text(metadata.title)
                        .font(AnvilFont.body.weight(.semibold))
                        .foregroundStyle(AnvilColor.textPrimary)
                        .lineLimit(1)
                    if metadata.usesAI {
                        StatusPill("KI", systemImage: "sparkles", tone: .ai)
                    }
                }
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
        .frame(height: AnvilSize.toolCardHeight, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                .fill(isHovering ? AnvilColor.elevated : AnvilColor.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                .strokeBorder(
                    isHovering ? AnvilColor.accent.opacity(0.5) : AnvilColor.border,
                    lineWidth: AnvilSize.hairline
                )
        }
        .contentShape(Rectangle())
    }
}
