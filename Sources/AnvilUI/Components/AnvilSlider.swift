import SwiftUI

/// Ein Regler mit dem Wert daneben.
///
/// Ein Regler ohne Zahl ist eine Vermutung: Man sieht, dass es „ungefähr in
/// der Mitte" steht, und weiß nicht, ob das 0,5 oder 0,55 ist. Beim
/// Nachbauen einer Einstellung — in einer Notiz, in einer zweiten App, im
/// Gespräch — ist genau das die Angabe, die fehlt.
public struct AnvilSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let format: (Double) -> String
    private let onEditingChanged: ((Bool) -> Void)?

    /// - Parameters:
    ///   - format: Wie der Wert rechts danebensteht. Voreingestellt mit einer
    ///     Nachkommastelle — das ist bei den üblichen Bereichen von 0 bis 1
    ///     die Auflösung, die man auch einstellen kann.
    ///   - onEditingChanged: `false`, sobald der Griff losgelassen wird. Wer
    ///     an einer Änderung etwas Teures hängt, wartet darauf statt auf jeden
    ///     Zwischenwert.
    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double = 0.1,
        format: @escaping (Double) -> String = { String(format: "%.1f", $0) },
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.format = format
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        HStack(spacing: AnvilSpacing.sm) {
            Slider(
                value: $value,
                in: range,
                step: step,
                onEditingChanged: { onEditingChanged?($0) }
            )

            Text(verbatim: format(value))
                .font(AnvilFont.caption.monospacedDigit())
                .foregroundStyle(AnvilColor.textSecondary)
                // Feste Breite, sonst wandert der Regler beim Ziehen, weil die
                // Zahl daneben mal drei und mal vier Zeichen breit ist.
                .frame(width: AnvilSize.sliderValueWidth, alignment: .trailing)
        }
    }

    /// Der Wert als Prozent — die zweite Form, die tatsächlich vorkommt.
    public static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded())) %"
    }
}
