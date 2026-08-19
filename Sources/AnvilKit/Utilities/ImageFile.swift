import AppKit
import Foundation

/// Turning an image into a file.
extension NSImage {
    /// The image as PNG bytes.
    public func pngData() throws -> Data {
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
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
