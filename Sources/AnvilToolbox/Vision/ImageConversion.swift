import AnvilKit
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Bilder umwandeln, verkleinern und dabei loswerden, was niemanden angeht.
public enum ImageConversion {
    /// Die Formate, die zur Auswahl stehen.
    public enum Format: String, CaseIterable, Codable, Sendable, Identifiable {
        case png
        case jpeg
        case heic
        case tiff

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .png: "PNG"
            case .jpeg: "JPEG"
            case .heic: "HEIC"
            case .tiff: "TIFF"
            }
        }

        public var pathExtension: String {
            switch self {
            case .png: "png"
            case .jpeg: "jpg"
            case .heic: "heic"
            case .tiff: "tiff"
            }
        }

        public var type: UTType {
            switch self {
            case .png: .png
            case .jpeg: .jpeg
            case .heic: .heic
            case .tiff: .tiff
            }
        }

        /// Ob eine Qualitätsstufe überhaupt etwas bewirkt. Bei PNG und TIFF
        /// ist der Regler sinnlos, also wird er dort nicht gezeigt.
        public var isLossy: Bool {
            self == .jpeg || self == .heic
        }

        public var explanation: String {
            switch self {
            case .png:
                localized("Verlustfrei, kann Transparenz. Für Bildschirmfotos und Grafiken.")
            case .jpeg:
                localized("Klein, verlustbehaftet, keine Transparenz. Was jedes Formular nimmt.")
            case .heic:
                localized("Deutlich kleiner als JPEG bei gleicher Güte — außerhalb von Apple aber nicht überall lesbar.")
            case .tiff:
                localized("Verlustfrei und groß. Für die Weitergabe an Druck und Bildbearbeitung.")
            }
        }
    }

    /// Wie stark verkleinert wird.
    public enum Scale: String, CaseIterable, Codable, Sendable, Identifiable {
        case original
        case half
        case quarter
        /// Die längere Kante auf einen festen Wert.
        case longestEdge

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .original: localized("Original")
            case .half: localized("Halbe Größe")
            case .quarter: localized("Viertel")
            case .longestEdge: localized("Längste Kante")
            }
        }
    }

    /// Was am Ende herauskommt.
    public struct Output: Sendable {
        public let data: Data
        public let pixelSize: CGSize
        public let format: Format

        public var byteCount: Int { data.count }
    }

    // MARK: - Rechnen

    /// Die Zielgröße für ein Bild.
    public static func targetSize(
        for size: CGSize,
        scale: Scale,
        longestEdge: Int
    ) -> CGSize {
        guard size.width > 0, size.height > 0 else { return size }

        switch scale {
        case .original:
            return size
        case .half:
            return rounded(CGSize(width: size.width / 2, height: size.height / 2))
        case .quarter:
            return rounded(CGSize(width: size.width / 4, height: size.height / 4))
        case .longestEdge:
            let longest = max(size.width, size.height)
            let wanted = CGFloat(max(1, longestEdge))
            guard wanted < longest else { return size }
            let factor = wanted / longest
            return rounded(CGSize(width: size.width * factor, height: size.height * factor))
        }
    }

    /// Mindestens ein Bildpunkt in jeder Richtung — ein Bild mit der Breite
    /// null lässt sich nicht kodieren.
    private static func rounded(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(1, size.width.rounded()),
            height: max(1, size.height.rounded())
        )
    }

    // MARK: - Umwandeln

    /// Wandelt ein Bild um und gibt die fertigen Bytes zurück.
    public static func convert(
        _ image: NSImage,
        to format: Format,
        scale: Scale = .original,
        longestEdge: Int = 2000,
        quality: Double = 0.85
    ) throws -> Output {
        guard let source = cgImage(from: image) else {
            throw AnvilError.invalidInput(localized("Das Bild ließ sich nicht lesen."))
        }
        return try encode(source, to: format, scale: scale, longestEdge: longestEdge, quality: quality)
    }

    /// Der gemeinsame Kern: verkleinern, kodieren, fertig.
    private static func encode(
        _ source: CGImage,
        to format: Format,
        scale: Scale,
        longestEdge: Int,
        quality: Double
    ) throws -> Output {
        let original = CGSize(width: source.width, height: source.height)
        let target = targetSize(for: original, scale: scale, longestEdge: longestEdge)
        let scaled = try redraw(source, to: target)

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            format.type.identifier as CFString,
            1,
            nil
        ) else {
            throw AnvilError.storage(
                localized("Für \(format.title) gibt es auf diesem Mac keinen Kodierer.")
            )
        }

        var options: [CFString: Any] = [:]
        if format.isLossy {
            options[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0.1), 1.0)
        }

        CGImageDestinationAddImage(destination, scaled, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw AnvilError.storage(localized("Das Bild ließ sich nicht schreiben."))
        }

        return Output(
            data: data as Data,
            pixelSize: CGSize(width: scaled.width, height: scaled.height),
            format: format
        )
    }

    /// Dasselbe für eine Datei auf der Platte.
    public static func convert(
        contentsOf url: URL,
        to format: Format,
        scale: Scale = .original,
        longestEdge: Int = 2000,
        quality: Double = 0.85
    ) throws -> Output {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw AnvilError.invalidInput(
                localized("„\(url.lastPathComponent)\" ließ sich nicht als Bild lesen.")
            )
        }
        return try encode(image, to: format, scale: scale, longestEdge: longestEdge, quality: quality)
    }

    /// Ein ganzer Stapel.
    public struct BatchResult: Sendable {
        public let url: URL
        public let output: Output?
        public let failure: String?

        public var succeeded: Bool { output != nil }
    }

    public static func convertAll(
        _ urls: [URL],
        to format: Format,
        scale: Scale = .original,
        longestEdge: Int = 2000,
        quality: Double = 0.85
    ) -> [BatchResult] {
        urls.map { url in
            do {
                let output = try convert(
                    contentsOf: url,
                    to: format,
                    scale: scale,
                    longestEdge: longestEdge,
                    quality: quality
                )
                return BatchResult(url: url, output: output, failure: nil)
            } catch let error as AnvilError {
                return BatchResult(url: url, output: nil, failure: error.message)
            } catch {
                return BatchResult(url: url, output: nil, failure: error.localizedDescription)
            }
        }
    }

    /// Zeichnet das Bild in der Zielgröße neu.
    private static func redraw(_ image: CGImage, to size: CGSize) throws -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        if width == image.width, height == image.height { return image }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AnvilError.unexpected(localized("Die Zeichenfläche ließ sich nicht anlegen."))
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let result = context.makeImage() else {
            throw AnvilError.unexpected(localized("Das verkleinerte Bild ließ sich nicht erzeugen."))
        }
        return result
    }

    /// Was an Metadaten in einer Datei steckt — für die Anzeige „das wäre
    /// mitgegangen".
    public static func metadataSummary(of data: Data) -> [String] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return [] }

        var found: [String] = []
        if properties[kCGImagePropertyGPSDictionary] != nil {
            found.append(localized("Aufnahmeort"))
        }
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if exif[kCGImagePropertyExifDateTimeOriginal] != nil {
                found.append(localized("Aufnahmezeit"))
            }
            if exif[kCGImagePropertyExifLensModel] != nil {
                found.append(localized("Objektiv"))
            }
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           tiff[kCGImagePropertyTIFFModel] != nil {
            found.append(localized("Kamera"))
        }
        return found
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        let size = image.size
        let width = Int(size.width)
        let height = Int(size.height)
        // Draw into an explicit 1× CGContext to avoid Retina scale doubling the pixel dimensions.
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
