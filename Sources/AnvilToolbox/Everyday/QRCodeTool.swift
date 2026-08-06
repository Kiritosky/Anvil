import AnvilKit
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Making and reading QR codes.
///
/// Core Image does both, which is why this is a small file: the interesting
/// parts are the error-correction trade-off and scaling the result up without
/// blurring it — a QR code renders at one module per pixel and looks like mush
/// at any interpolated size.
public enum QRCode {
    /// How much of the code may be damaged and still be readable.
    public enum Correction: String, Codable, CaseIterable, Sendable, Identifiable {
        case low, medium, quartile, high

        public var id: String { rawValue }

        /// The letter Core Image expects.
        var level: String {
            switch self {
            case .low: "L"
            case .medium: "M"
            case .quartile: "Q"
            case .high: "H"
            }
        }

        public var title: String {
            switch self {
            case .low: localized("Klein (7 %)")
            case .medium: localized("Mittel (15 %)")
            case .quartile: localized("Groß (25 %)")
            case .high: localized("Sehr groß (30 %)")
            }
        }

        public var explanation: String {
            switch self {
            case .low:
                localized("Kleinstes Muster. Für Bildschirme, wo nichts verkratzt.")
            case .medium:
                localized("Der übliche Kompromiss.")
            case .quartile:
                localized("Für Aufkleber und Ausdrucke, die etwas abbekommen.")
            case .high:
                localized("Verträgt ein Logo in der Mitte oder einen Riss.")
            }
        }
    }

    /// Renders `text` as a QR code, `size` points on a side.
    ///
    /// - Throws: ``AnvilError/invalidInput(_:)`` when the text is empty or too
    ///   long for the format — around 2 900 bytes at the lowest correction
    ///   level, far less at the highest.
    public static func image(for text: String, correction: Correction = .medium, size: CGFloat = 512) throws -> NSImage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AnvilError.invalidInput(localized("Ohne Text gibt es nichts zu kodieren."))
        }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = correction.level

        guard let output = filter.outputImage else {
            throw AnvilError.invalidInput(
                localized("Der Text passt nicht in einen QR-Code — er ist zu lang.")
            )
        }

        // Nearest-neighbour by scaling the CIImage itself: every module has to
        // stay a hard-edged square, or scanners lose it.
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            throw AnvilError.storage(localized("Das Bild konnte nicht erzeugt werden."))
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }

    /// Reads every QR code in an image.
    public static func read(_ image: NSImage) -> [String] {
        guard let data = image.tiffRepresentation, let ciImage = CIImage(data: data) else {
            return []
        }

        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )

        return (detector?.features(in: ciImage) ?? [])
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            .filter { !$0.isEmpty }
    }

    /// Writes the code next to the app's other exports and returns its URL.
    @discardableResult
    public static func export(_ image: NSImage, named name: String) throws -> URL {
        AppPaths.bootstrap()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw AnvilError.storage(localized("Das Bild konnte nicht als PNG gesichert werden."))
        }

        let url = AppPaths.exports.appending(path: "\(name).png")
        do {
            try png.write(to: url)
        } catch {
            throw AnvilError.storage(localized("Der Export ist fehlgeschlagen: \(error.localizedDescription)"))
        }
        return url
    }
}

// MARK: - Settings keys

extension SettingKey {
    public static var qrCorrection: SettingKey<QRCode.Correction> {
        SettingKey<QRCode.Correction>("qr.correction", default: .medium)
    }
}
