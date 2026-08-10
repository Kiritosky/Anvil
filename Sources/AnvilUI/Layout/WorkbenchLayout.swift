import AnvilKit
import AppKit
import SwiftUI

/// Which way a workbench splits its two panes.
public enum WorkbenchOrientation: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Panes side by side — good on wide displays.
    case horizontal
    /// Panes stacked — good for long-form text and narrow windows.
    case vertical

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .horizontal: localized("Nebeneinander")
        case .vertical: localized("Untereinander")
        }
    }

    public var systemImage: String {
        switch self {
        case .horizontal: "rectangle.split.2x1"
        case .vertical: "rectangle.split.1x2"
        }
    }

    public mutating func toggle() {
        self = self == .horizontal ? .vertical : .horizontal
    }
}

/// Two resizable panes: input on one side, result on the other.
///
/// This is the shape most tools take — paste something, get something back —
/// so it is a layout primitive rather than something each tool reinvents. The
/// split position is draggable and remembered per tool.
public struct WorkbenchLayout<Primary: View, Secondary: View>: View {
    @Binding private var orientation: WorkbenchOrientation
    private let storageKey: String?
    private let minimumFraction: CGFloat
    private let primary: Primary
    private let secondary: Secondary

    @State private var fraction: CGFloat = 0.5
    @State private var dragStartFraction: CGFloat?

    private static var splitterThickness: CGFloat { 10 }

    public init(
        orientation: Binding<WorkbenchOrientation>,
        storageKey: String? = nil,
        minimumFraction: CGFloat = 0.2,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self._orientation = orientation
        self.storageKey = storageKey
        self.minimumFraction = minimumFraction
        self.primary = primary()
        self.secondary = secondary()
    }

    public var body: some View {
        GeometryReader { proxy in
            let total = orientation == .horizontal ? proxy.size.width : proxy.size.height
            let available = max(0, total - Self.splitterThickness)
            let primaryLength = (available * clampedFraction).rounded()

            layout {
                primary
                    .frame(
                        width: orientation == .horizontal ? primaryLength : nil,
                        height: orientation == .vertical ? primaryLength : nil
                    )

                splitter(total: available)

                secondary
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .animation(AnvilMotion.springy, value: orientation)
        .onAppear(perform: restoreFraction)
    }

    private var layout: AnyLayout {
        orientation == .horizontal
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))
    }

    private var clampedFraction: CGFloat {
        min(max(fraction, minimumFraction), 1 - minimumFraction)
    }

    private func splitter(total: CGFloat) -> some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(AnvilColor.separator)
                .frame(
                    width: orientation == .horizontal ? 1 : 28,
                    height: orientation == .horizontal ? 28 : 1
                )
                .opacity(dragStartFraction == nil ? 0.9 : 0)
            Capsule()
                .fill(AnvilColor.accent)
                .frame(
                    width: orientation == .horizontal ? 3 : 40,
                    height: orientation == .horizontal ? 40 : 3
                )
                .opacity(dragStartFraction == nil ? 0 : 1)
        }
        .frame(
            width: orientation == .horizontal ? Self.splitterThickness : nil,
            height: orientation == .vertical ? Self.splitterThickness : nil
        )
        .frame(
            maxWidth: orientation == .vertical ? .infinity : nil,
            maxHeight: orientation == .horizontal ? .infinity : nil
        )
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                (orientation == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    guard total > 0 else { return }
                    let start = dragStartFraction ?? clampedFraction
                    if dragStartFraction == nil { dragStartFraction = start }
                    let delta = orientation == .horizontal
                        ? value.translation.width
                        : value.translation.height
                    fraction = min(max(start + delta / total, minimumFraction), 1 - minimumFraction)
                }
                .onEnded { _ in
                    dragStartFraction = nil
                    persistFraction()
                }
        )
        .accessibilityLabel("Teiler verschieben")
    }

    // MARK: - Persistence

    private var defaultsKey: String? {
        storageKey.map { "anvil.workbench.\($0).\(orientation.rawValue)" }
    }

    private func restoreFraction() {
        guard let defaultsKey, let stored = UserDefaults.standard.object(forKey: defaultsKey) as? Double
        else { return }
        fraction = CGFloat(stored)
    }

    private func persistFraction() {
        guard let defaultsKey else { return }
        UserDefaults.standard.set(Double(fraction), forKey: defaultsKey)
    }
}

/// The control that flips a workbench between side-by-side and stacked.
///
/// Lives in the tool's header actions, so the toggle sits in the same spot in
/// every tool that has one.
public struct WorkbenchOrientationPicker: View {
    @Binding private var orientation: WorkbenchOrientation

    public init(orientation: Binding<WorkbenchOrientation>) {
        self._orientation = orientation
    }

    public var body: some View {
        Button {
            withAnimation(AnvilMotion.springy) { orientation.toggle() }
        } label: {
            Image(systemName: orientation.systemImage)
        }
        .buttonStyle(AnvilIconButtonStyle())
        .anvilHelp(verbatim: localized("Anordnung: \(orientation.title)"))
        .keyboardShortcut("\\", modifiers: [.command, .option])
    }
}
