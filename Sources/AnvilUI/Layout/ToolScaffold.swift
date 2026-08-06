import AnvilKit
import SwiftUI

/// The frame every tool is built in.
///
/// A tool supplies three things and gets a consistent screen for free: the
/// header (icon, title, subtitle), a content area, an optional inspector column
/// on the right for options, and optional header actions.
///
/// ```swift
/// ToolScaffold(metadata: metadata) {
///     WorkbenchLayout(orientation: $orientation) { input } secondary: { output }
/// } inspector: {
///     InspectorSection("Stil") { … }
/// } actions: {
///     AnvilButton("Ausführen", systemImage: "play.fill", role: .primary) { run() }
/// }
/// ```
///
/// Tools never draw their own header, never pick their own page margins, and
/// never invent a second place to put options. That is the whole point.
public struct ToolScaffold<Content: View, Inspector: View, Actions: View>: View {
    @Environment(\.anvilTheme) private var theme

    private let title: String
    private let subtitle: String
    private let systemImage: String
    private let tone: AnvilTone
    private let content: Content
    private let inspector: Inspector
    private let actions: Actions

    /// Persisted per tool so the inspector stays how the user left it.
    @State private var isInspectorVisible: Bool
    private let inspectorStorageKey: String

    private var hasInspector: Bool { Inspector.self != EmptyView.self }

    public init(
        title: String,
        subtitle: String = "",
        systemImage: String,
        tone: AnvilTone = .accent,
        storageKey: String = "",
        @ViewBuilder content: () -> Content,
        @ViewBuilder inspector: () -> Inspector,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tone = tone
        self.content = content()
        self.inspector = inspector()
        self.actions = actions()
        self.inspectorStorageKey = "anvil.inspector." + (storageKey.isEmpty ? title : storageKey)
        _isInspectorVisible = State(
            initialValue: UserDefaults.standard.object(
                forKey: "anvil.inspector." + (storageKey.isEmpty ? title : storageKey)
            ) as? Bool ?? true
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            ToolHeaderBar(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tone: tone
            ) {
                actions
                if hasInspector {
                    Divider().frame(height: 18)
                    inspectorToggle
                }
            }

            Divider()

            HStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(theme.density.contentPadding)

                if hasInspector, isInspectorVisible {
                    Divider()
                    InspectorPane { inspector }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AnvilColor.canvas)
        .animation(AnvilMotion.springy, value: isInspectorVisible)
    }

    private var inspectorToggle: some View {
        Button {
            isInspectorVisible.toggle()
            UserDefaults.standard.set(isInspectorVisible, forKey: inspectorStorageKey)
        } label: {
            Label("Optionen", systemImage: "sidebar.trailing")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(AnvilIconButtonStyle(isActive: isInspectorVisible))
        .anvilHelp(isInspectorVisible ? "Optionen ausblenden" : "Optionen einblenden")
        .keyboardShortcut("0", modifiers: [.command, .option])
    }
}

// MARK: - Convenience initialisers

extension ToolScaffold where Inspector == EmptyView, Actions == EmptyView {
    public init(
        title: String,
        subtitle: String = "",
        systemImage: String,
        tone: AnvilTone = .accent,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tone: tone,
            content: content,
            inspector: { EmptyView() },
            actions: { EmptyView() }
        )
    }
}

extension ToolScaffold where Inspector == EmptyView {
    public init(
        title: String,
        subtitle: String = "",
        systemImage: String,
        tone: AnvilTone = .accent,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tone: tone,
            content: content,
            inspector: { EmptyView() },
            actions: actions
        )
    }
}

extension ToolScaffold where Actions == EmptyView {
    public init(
        title: String,
        subtitle: String = "",
        systemImage: String,
        tone: AnvilTone = .accent,
        storageKey: String = "",
        @ViewBuilder content: () -> Content,
        @ViewBuilder inspector: () -> Inspector
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tone: tone,
            storageKey: storageKey,
            content: content,
            inspector: inspector,
            actions: { EmptyView() }
        )
    }
}

// MARK: - Metadata-driven initialisers

extension ToolScaffold {
    /// Builds the header straight from the tool's registry metadata, so the
    /// sidebar entry and the tool screen can never drift apart.
    public init(
        metadata: ToolMetadata,
        tone: AnvilTone? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder inspector: () -> Inspector,
        @ViewBuilder actions: () -> Actions
    ) {
        self.init(
            title: metadata.title,
            subtitle: metadata.subtitle,
            systemImage: metadata.systemImage,
            tone: tone ?? (metadata.usesAI ? .ai : .accent),
            storageKey: metadata.id.rawValue,
            content: content,
            inspector: inspector,
            actions: actions
        )
    }
}

extension ToolScaffold where Inspector == EmptyView, Actions == EmptyView {
    public init(metadata: ToolMetadata, tone: AnvilTone? = nil, @ViewBuilder content: () -> Content) {
        self.init(
            title: metadata.title,
            subtitle: metadata.subtitle,
            systemImage: metadata.systemImage,
            tone: tone ?? (metadata.usesAI ? .ai : .accent),
            content: content
        )
    }
}

extension ToolScaffold where Actions == EmptyView {
    public init(
        metadata: ToolMetadata,
        tone: AnvilTone? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder inspector: () -> Inspector
    ) {
        self.init(
            title: metadata.title,
            subtitle: metadata.subtitle,
            systemImage: metadata.systemImage,
            tone: tone ?? (metadata.usesAI ? .ai : .accent),
            storageKey: metadata.id.rawValue,
            content: content,
            inspector: inspector
        )
    }
}

extension ToolScaffold where Inspector == EmptyView {
    public init(
        metadata: ToolMetadata,
        tone: AnvilTone? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        self.init(
            title: metadata.title,
            subtitle: metadata.subtitle,
            systemImage: metadata.systemImage,
            tone: tone ?? (metadata.usesAI ? .ai : .accent),
            content: content,
            actions: actions
        )
    }
}
