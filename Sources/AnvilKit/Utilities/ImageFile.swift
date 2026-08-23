import AppKit
import Foundation

/// Turning an image into a file.
extension NSImage {
    /// The image as PNG bytes.
    public func pngData() throws -> Data {
        let width = Int(size.width)
        let height = Int(size.height)
        // Draw at 1× to avoid Retina scale doubling the pixel dimensions.
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw AnvilError.storage(localized("Das Bild konnte nicht als PNG gesichert werden."))
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AnvilError.storage(localized("Das Bild konnte nicht als PNG gesichert werden."))
        }
        return png
    }

    /// Writes the image as a PNG and hands back where it landed.
    @discardableResult
    public func writePNG(to url: URL) throws -> URL {
        let data = try pngData()
        do {
            try data.write(to: url)
        } catch {
            throw AnvilError.storage(
                localized("Der Export ist fehlgeschlagen: \(error.localizedDescription)")
            )
        }
        return url
    }
}
