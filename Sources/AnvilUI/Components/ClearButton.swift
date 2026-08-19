import SwiftUI

/// Der Knopf, der eine Liste leert.
public struct ClearButton: View {
    private let help: LocalizedStringKey
    private let action: () -> Void

    public init(help: LocalizedStringKey = "Liste leeren", action: @escaping () -> Void) {
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
        }
        .buttonStyle(AnvilIconButtonStyle(tone: .danger))
        .anvilHelp(help)
    }
}
