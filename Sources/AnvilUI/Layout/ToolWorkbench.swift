import SwiftUI

/// The shape most tools have: two panes side by side, a status bar underneath.
public struct ToolWorkbench<Primary: View, Secondary: View, Status: View>: View {
    @Binding private var orientation: WorkbenchOrientation
    private let storageKey: String?
    private let primary: Primary
    private let secondary: Secondary
    private let status: Status

    public init(
        orientation: Binding<WorkbenchOrientation>,
        storageKey: String? = nil,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary,
        @ViewBuilder status: () -> Status
    ) {
        self._orientation = orientation
        self.storageKey = storageKey
        self.primary = primary()
        self.secondary = secondary()
        self.status = status()
    }

    /// For tools whose layout never changes — an image next to its text, say.
    public init(
        storageKey: String? = nil,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary,
        @ViewBuilder status: () -> Status
    ) {
        self.init(
            orientation: .constant(.horizontal),
            storageKey: storageKey,
            primary: primary,
            secondary: secondary,
            status: status
        )
    }

    public var body: some View {
        VStack(spacing: AnvilSpacing.md) {
            WorkbenchLayout(orientation: $orientation, storageKey: storageKey) {
                primary
                    .padding(.trailing, orientation == .horizontal ? AnvilSpacing.sm : 0)
                    .padding(.bottom, orientation == .vertical ? AnvilSpacing.sm : 0)
            } secondary: {
                secondary
                    .padding(.leading, orientation == .horizontal ? AnvilSpacing.sm : 0)
                    .padding(.top, orientation == .vertical ? AnvilSpacing.sm : 0)
            }

            status
        }
    }
}

extension ToolWorkbench where Status == EmptyView {
    /// Without a status bar.
    public init(
        orientation: Binding<WorkbenchOrientation>,
        storageKey: String? = nil,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.init(
            orientation: orientation,
            storageKey: storageKey,
            primary: primary,
            secondary: secondary,
            status: { EmptyView() }
        )
    }
}
