import SwiftUI

/// The label above a group: small capitals, wide, quiet.
public struct AnvilSectionHeader: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let accessory: AnyView?

    public init(_ title: LocalizedStringKey, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = nil
    }

    public init<Accessory: View>(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = AnyView(accessory())
    }

    public var body: some View {
        HStack(spacing: AnvilSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(AnvilFont.micro)
            }
            Text(title)
                .font(AnvilFont.label)
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer(minLength: AnvilSpacing.sm)

            if let accessory {
                accessory
            }
        }
        .foregroundStyle(AnvilColor.textSecondary)
    }
}

/// A page-level heading — the line above a group of cards.
public struct AnvilPageHeading: View {
    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey?

    public init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
            Text(title)
                .font(AnvilFont.heading)
                .foregroundStyle(AnvilColor.textPrimary)

            if let subtitle {
                Text(subtitle)
                    .font(AnvilFont.body)
                    .foregroundStyle(AnvilColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
