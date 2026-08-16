import SwiftUI

/// Der Knopf, der eine Liste leert.
///
/// Elf Stellen hatten dafür denselben Knopf abgeschrieben — und dabei
/// auseinandergelaufen: In manchen Werkzeugen war er rot, in anderen grau,
/// obwohl er überall dasselbe tut. Wegwerfen ist rot; das ist die einzige
/// Farbe, an der man vor dem Klicken erkennt, dass danach etwas weg ist.
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
