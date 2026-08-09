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

            // Das Kürzel steht dort, wo es gedrückt wird — sonst weiß niemand,
            // dass es die Zeile überhaupt gibt.
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
        // Der Stern liegt über der Karte statt in ihr: eine Schaltfläche in der
        // Beschriftung einer anderen Schaltfläche bekommt den Klick nicht
        // zuverlässig ab.
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
                ToolIconBadge(
                    systemImage: metadata.systemImage,
                    tone: metadata.usesAI ? .ai : .accent,
                    size: AnvilSize.toolIconLarge
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
            RoundedRectangle(cornerRadius: AnvilRadius.lg, style: .continuous)
                .fill(isHovering ? AnvilColor.field : AnvilColor.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AnvilRadius.lg, style: .continuous)
                .strokeBorder(
                    isHovering ? AnvilColor.borderFocused : AnvilColor.border,
                    lineWidth: AnvilSize.hairline
                )
        }
        .contentShape(Rectangle())
    }
}
