import Foundation

/// Zahlen so lesen, wie sie in Tabellen stehen: mit Tausenderpunkten,
/// deutschem Komma und angehängten Einheiten wie „MB".
public enum NumericText {
    /// Die ganze Zeichenkette muss eine Zahl sein — für Summen und
    /// Mittelwerte, wo eine halb gelesene Zelle das Ergebnis verfälscht.
    public static func value(in text: String) -> Double? {
        let work = normalised(text)
        guard !work.isEmpty else { return nil }
        return Double(work)
    }

    /// Nimmt die Zahl am Anfang und rechnet eine angehängte Größeneinheit
    /// ein: „1,2 MB" steht damit hinter „900 kB".
    public static func leadingValue(in text: String) -> Double? {
        var rest = Substring(normalised(text))
        var number = ""

        if rest.first == "-" || rest.first == "+" {
            number.append(rest.removeFirst())
        }
        while let character = rest.first, character.isASCII, character.isNumber || character == "." {
            number.append(rest.removeFirst())
        }

        guard let parsed = Double(number) else { return nil }
        return parsed * factor(of: rest.prefix { $0.isLetter })
    }

    /// Trennzeichen vereinheitlichen: Steht das Komma hinter dem Punkt, ist es
    /// das Dezimalzeichen — sonst umgekehrt.
    private static func normalised(_ text: String) -> String {
        var work = text.trimmingCharacters(in: .whitespaces)
        guard !work.isEmpty else { return "" }

        work = work.replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")

        switch (work.lastIndex(of: ","), work.lastIndex(of: ".")) {
        case let (comma?, dot?):
            if comma > dot {
                work = work.replacingOccurrences(of: ".", with: "")
                work = work.replacingOccurrences(of: ",", with: ".")
            } else {
                work = work.replacingOccurrences(of: ",", with: "")
            }
        case (.some, nil):
            work = work.replacingOccurrences(of: ",", with: ".")
        default:
            break
        }

        return work
    }

    private static func factor(of unit: Substring) -> Double {
        switch unit.lowercased() {
        case "kb": 1_000
        case "mb": 1_000_000
        case "gb": 1_000_000_000
        case "tb": 1_000_000_000_000
        case "pb": 1_000_000_000_000_000
        case "kib": 1_024
        case "mib": 1_048_576
        case "gib": 1_073_741_824
        case "tib": 1_099_511_627_776
        case "pib": 1_125_899_906_842_624
        default: 1
        }
    }
}
