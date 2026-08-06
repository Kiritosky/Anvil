import AppKit
import Foundation

/// Turning an image into a file.
///
/// Two tools had their own copy of the same four lines — TIFF out of the
/// image, bitmap out of the TIFF, PNG out of the bitmap, and an error message
/// for the case where one of them fails. It is the kind of duplication that
/// stays harmless right up to the moment one copy learns something the other
/// does not.
extension NSImage {
    /// The image as PNG bytes.
    ///
    /// Throws rather than returning `nil`: every caller turned the `nil` into
    /// the same error anyway, and one of them is on a path where a silent
    /// failure would look like a saved file.
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
