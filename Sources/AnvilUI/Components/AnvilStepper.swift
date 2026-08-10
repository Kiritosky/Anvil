import AppKit
import SwiftUI

/// Eine ganze Zahl einstellen.
///
/// SwiftUIs `Stepper` wäre kürzer und sieht im Inspektor falsch aus: winzige
/// Pfeile, die nicht zur Höhe eines Eingabefelds passen, und der Wert steht
/// daneben statt darin. Hier ist der Wert das Feld, und die beiden Knöpfe
/// sitzen darin — dieselbe Höhe wie jedes andere Bedienelement.
public struct AnvilStepper: View {
    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let step: Int
    private let format: (Int) -> String

    /// Wie viel ein Klick mit gedrückter Wahltaste zählt.
    ///
    /// Ein Bereich bis 10 000 wäre sonst nicht zu bedienen. Zehnfach und nicht
    /// hundertfach, weil man den Sprung noch überblicken können soll.
    private static let modifierFactor = 10

    /// - Parameter format: Wie der Wert dasteht. Standardmäßig die Zahl selbst;
    ///   ein Werkzeug, das führende Nullen zeigt, gibt hier etwas anderes mit.
    public init(
        value: Binding<Int>,
        in range: ClosedRange<Int>,
        step: Int = 1,
        format: @escaping (Int) -> String = { "\($0)" }
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    public var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: format(value))
                .font(AnvilFont.mono)
                .foregroundStyle(AnvilColor.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, AnvilSpacing.sm)

            Spacer(minLength: 0)

            button("minus", sign: -1, isEnabled: value > range.lowerBound)
            Divider().frame(height: AnvilSize.dividerHeight)
            button("plus", sign: 1, isEnabled: value < range.upperBound)
        }
        .frame(height: AnvilSize.controlHeight)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                .fill(AnvilColor.field)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                .strokeBorder(AnvilColor.border, lineWidth: AnvilSize.hairline)
        }
        .anvilHelp("Mit der Wahltaste in größeren Schritten")
    }

    private func button(_ systemImage: String, sign: Int, isEnabled: Bool) -> some View {
        Button {
            change(sign: sign)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .frame(width: AnvilSize.controlHeight, height: AnvilSize.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? AnvilColor.textSecondary : AnvilColor.textTertiary)
        .disabled(!isEnabled)
    }

    private func change(sign: Int) {
        // Der Zustand der Wahltaste wird beim Klick gelesen, nicht über eine
        // Geste verfolgt: eine Geste über einem Knopf schluckt gern den Klick
        // selbst.
        let factor = NSEvent.modifierFlags.contains(.option) ? Self.modifierFactor : 1
        let next = value + sign * step * factor
        value = min(range.upperBound, max(range.lowerBound, next))
    }
}
