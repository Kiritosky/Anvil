import AnvilKit
import Foundation

/// Der Satz Bildgrößen, den Xcode für ein App-Symbol verlangt.
///
/// Von Hand ist das zwanzigmal exportieren, zwanzigmal richtig benennen und
/// danach eine `Contents.json`, in der ein Tippfehler dazu führt, dass Xcode
/// das ganze Symbol übergeht. Die Liste steht deshalb hier als Daten und nicht
/// als Anleitung.
public struct IconSet: Sendable {
    /// Wofür der Satz gedacht ist.
    public enum Platform: String, Sendable, Hashable, CaseIterable, Identifiable {
        case macOS
        case iOS

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .macOS: "macOS"
            case .iOS: "iOS"
            }
        }

        public var systemImage: String {
            switch self {
            case .macOS: "laptopcomputer"
            case .iOS: "iphone"
            }
        }
    }

    /// Eine einzelne Größe im Satz.
    public struct Item: Sendable, Hashable, Identifiable {
        /// Wie Xcode das Gerät nennt: `mac`, `iphone`, `ipad`, `ios-marketing`.
        public let idiom: String
        /// Die Kantenlänge in Punkten — bei iPad-Symbolen auch mit Komma.
        public let points: Double
        public let scale: Int

        public init(idiom: String, points: Double, scale: Int) {
            self.idiom = idiom
            self.points = points
            self.scale = scale
        }

        /// Die Kantenlänge in Bildpunkten — das, was wirklich gezeichnet wird.
        public var pixels: Int { Int((points * Double(scale)).rounded()) }

        /// „16x16", „83.5x83.5" — die Schreibweise, die Xcode erwartet.
        public var sizeText: String {
            let edge = points == points.rounded()
                ? "\(Int(points))"
                : "\(points)"
            return "\(edge)x\(edge)"
        }

        public var scaleText: String { "\(scale)x" }

        /// `icon_32x32@2x.png` — die übliche Schreibweise.
        public var fileName: String {
            let suffix = scale > 1 ? "@\(scale)x" : ""
            return "icon_\(sizeText)\(suffix).png"
        }

        public var id: String { "\(idiom)-\(sizeText)-\(scaleText)" }
    }

    /// Die Größen, die Xcode für ein macOS-Symbol verlangt.
    public static let macOSItems: [Item] = [16, 32, 128, 256, 512].flatMap { points in
        [1, 2].map { scale in Item(idiom: "mac", points: Double(points), scale: scale) }
    }

    /// Die Größen für iOS.
    ///
    /// Der 1024er hat das Kürzel `ios-marketing` und ist der einzige, der
    /// nicht aufs Gerät geht — er steht im App Store. Fehlt er, lässt sich die
    /// App nicht hochladen; das merkt man erfahrungsgemäß freitagabends.
    public static let iOSItems: [Item] = [
        Item(idiom: "iphone", points: 20, scale: 2),
        Item(idiom: "iphone", points: 20, scale: 3),
        Item(idiom: "iphone", points: 29, scale: 2),
        Item(idiom: "iphone", points: 29, scale: 3),
        Item(idiom: "iphone", points: 40, scale: 2),
        Item(idiom: "iphone", points: 40, scale: 3),
        Item(idiom: "iphone", points: 60, scale: 2),
        Item(idiom: "iphone", points: 60, scale: 3),
        Item(idiom: "ipad", points: 20, scale: 1),
        Item(idiom: "ipad", points: 20, scale: 2),
        Item(idiom: "ipad", points: 29, scale: 1),
        Item(idiom: "ipad", points: 29, scale: 2),
        Item(idiom: "ipad", points: 40, scale: 1),
        Item(idiom: "ipad", points: 40, scale: 2),
        Item(idiom: "ipad", points: 76, scale: 2),
        Item(idiom: "ipad", points: 83.5, scale: 2),
        Item(idiom: "ios-marketing", points: 1024, scale: 1)
    ]

    public static func items(for platform: Platform) -> [Item] {
        switch platform {
        case .macOS: macOSItems
        case .iOS: iOSItems
        }
    }

    /// Die Bildpunktgrößen, die wirklich gezeichnet werden müssen.
    ///
    /// Weniger als die Liste lang ist: `32x32@1x` und `16x16@2x` sind
    /// dieselben zweiunddreißig Bildpunkte. Gezeichnet wird jede Größe einmal,
    /// geschrieben so oft, wie sie gebraucht wird.
    public static func pixelSizes(for platform: Platform) -> [Int] {
        Array(Set(items(for: platform).map(\.pixels))).sorted()
    }

    /// Die größte Kantenlänge im Satz — so groß sollte die Vorlage sein.
    public static func largestPixelSize(for platform: Platform) -> Int {
        pixelSizes(for: platform).last ?? 0
    }

    public static let folderName = "AppIcon.appiconset"

    /// Die `Contents.json`, die Xcode neben den Bildern erwartet.
    ///
    /// Von Hand geschrieben statt über `JSONEncoder`: Die Datei hat eine feste
    /// Reihenfolge, in der Xcode sie selbst schreibt, und eine Datei, die sich
    /// beim ersten Öffnen in Xcode umsortiert, sieht im Diff aus wie eine
    /// Änderung.
    public static func contentsJSON(for platform: Platform) -> String {
        let entries = items(for: platform).map { item in
            """
                {
                  "filename" : "\(item.fileName)",
                  "idiom" : "\(item.idiom)",
                  "scale" : "\(item.scaleText)",
                  "size" : "\(item.sizeText)"
                }
            """
        }

        return """
        {
          "images" : [
        \(entries.joined(separator: ",\n"))
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }

        """
    }

    // MARK: - Ausgeben

    public static let reportColumns = [
        localized("Datei"),
        localized("Größe"),
        localized("Maßstab"),
        localized("Bildpunkte")
    ]

    public static func rows(for platform: Platform) -> [[String]] {
        items(for: platform).map { item in
            [item.fileName, item.sizeText, item.scaleText, "\(item.pixels)"]
        }
    }
}
