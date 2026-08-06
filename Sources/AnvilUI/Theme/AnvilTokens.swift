import SwiftUI

// MARK: - Spacing

/// The spacing scale. Every gap and inset in the app comes from here.
///
/// Six steps on a 4pt grid. If a layout needs something in between, the layout
/// is wrong — not the scale.
public enum AnvilSpacing {
    /// 2pt — hairline separation inside a control.
    public static let xxs: CGFloat = 2
    /// 4pt — icon to its label.
    public static let xs: CGFloat = 4
    /// 8pt — related controls in a row.
    public static let sm: CGFloat = 8
    /// 12pt — default gap inside a card.
    public static let md: CGFloat = 12
    /// 16pt — card padding, gap between form rows.
    public static let lg: CGFloat = 16
    /// 24pt — gap between sections.
    public static let xl: CGFloat = 24
    /// 32pt — page margins, empty-state breathing room.
    public static let xxl: CGFloat = 32
}

// MARK: - Radius

/// Corner radii. Nested shapes step down one level so corners stay concentric.
public enum AnvilRadius {
    /// 6pt — chips, small buttons, inline badges.
    public static let sm: CGFloat = 6
    /// 10pt — inputs, list rows.
    public static let md: CGFloat = 10
    /// 14pt — cards and panes.
    public static let lg: CGFloat = 14
    /// 20pt — sheets and floating panels.
    public static let xl: CGFloat = 20
}

// MARK: - Sizes

/// Fixed sizes that recur across components.
public enum AnvilSize {
    /// Height of a standard control row.
    public static let controlHeight: CGFloat = 28
    /// Height of the tool header bar.
    public static let headerHeight: CGFloat = 60
    /// Height of the status bar at the bottom of a tool.
    public static let statusBarHeight: CGFloat = 32
    /// Width of the options column on the right of a tool.
    public static let inspectorWidth: CGFloat = 300
    /// Sidebar width in the main window.
    public static let sidebarWidth: CGFloat = 248
    /// Minimum comfortable height for a text pane.
    public static let paneMinHeight: CGFloat = 160
    /// Width of the leading field in a two-field list row.
    public static let listFieldWidth: CGFloat = 170
    /// Height a secondary list inside a pane is capped at, so the main content
    /// above it keeps the room.
    public static let secondaryListHeight: CGFloat = 140
    /// A thumbnail in a filmstrip: 16:10, the shape most screens are.
    public static let thumbnailWidth: CGFloat = 96
    public static let thumbnailHeight: CGFloat = 60
    /// Square size of a tool icon in the sidebar.
    public static let toolIcon: CGFloat = 22
    /// A plain border: the line between a surface and what is next to it.
    public static let hairline: CGFloat = 1
    /// A border that means something — focus, or a drop target waiting for the
    /// mouse to let go. Thick enough to read as deliberate at a glance.
    public static let focusRing: CGFloat = 2
}

// MARK: - Typography

/// The type scale.
///
/// Names describe the role, never the size, so a later density change or a
/// design tweak happens here and nowhere else.
public enum AnvilFont {
    /// The app wordmark. The only place rounded design is used.
    public static let wordmark = Font.system(size: 17, weight: .semibold, design: .rounded)
    /// Tool title in the header.
    public static let title = Font.system(size: 19, weight: .semibold)
    /// Section heading inside a tool.
    public static let sectionTitle = Font.system(size: 13, weight: .semibold)
    /// Sidebar and list row label.
    public static let rowTitle = Font.system(size: 13, weight: .medium)
    /// Standard body copy.
    public static let body = Font.system(size: 13)
    /// Supporting copy under a title.
    public static let caption = Font.system(size: 11)
    /// All-caps label above a group of controls.
    public static let label = Font.system(size: 10, weight: .semibold)
    /// Monospaced text: code, transcripts, JSON, hashes.
    public static let mono = Font.system(size: 12.5, design: .monospaced)
    /// Smaller monospaced text for inline values.
    public static let monoSmall = Font.system(size: 11, design: .monospaced)
}

// MARK: - Motion

/// Animation tokens.
///
/// Three speeds, one spring. Consistent motion is most of what makes a
/// component library feel like a single app rather than a pile of views.
public enum AnvilMotion {
    /// 0.12s — hover and press feedback.
    public static let quick = Animation.easeOut(duration: 0.12)
    /// 0.2s — panes appearing, banners sliding in.
    public static let standard = Animation.easeInOut(duration: 0.2)
    /// Springy — anything the user drags or toggles between layouts.
    public static let springy = Animation.spring(response: 0.34, dampingFraction: 0.82)
    /// Continuous — progress shimmer while a model streams.
    public static let pulse = Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true)
}
