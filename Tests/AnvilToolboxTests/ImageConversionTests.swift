import AnvilKit
import AppKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import AnvilToolbox

@Suite("ImageConversion")
struct ImageConversionTests {
    private func image(width: Int, height: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        // Etwas Struktur, damit ein verlustbehaftetes Format überhaupt etwas
        // zu tun hat — eine einfarbige Fläche komprimiert jedes Verfahren
        // gleich gut, und der Test würde nichts aussagen.
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: width / 2, height: height / 3).fill()
        image.unlockFocus()
        return image
    }

    // MARK: - Die Rechnung

    @Test
    func originalKeepsItsSize() {
        let size = CGSize(width: 1234, height: 567)
        #expect(ImageConversion.targetSize(for: size, scale: .original, longestEdge: 100) == size)
    }

    @Test
    func halfAndQuarterDivide() {
        let size = CGSize(width: 800, height: 600)
        #expect(ImageConversion.targetSize(for: size, scale: .half, longestEdge: 0)
            == CGSize(width: 400, height: 300))
        #expect(ImageConversion.targetSize(for: size, scale: .quarter, longestEdge: 0)
            == CGSize(width: 200, height: 150))
    }

    /// Das Seitenverhältnis muss bleiben — sonst ist das Bild verzerrt, und
    /// das sieht man sofort.
    @Test
    func longestEdgeKeepsTheAspectRatio() {
        let result = ImageConversion.targetSize(
            for: CGSize(width: 4000, height: 3000),
            scale: .longestEdge,
            longestEdge: 1000
        )
        #expect(result == CGSize(width: 1000, height: 750))
    }

    @Test
    func longestEdgeUsesTheActualLongerSide() {
        // Hochkant: die Höhe ist die längere Kante.
        let result = ImageConversion.targetSize(
            for: CGSize(width: 1500, height: 3000),
            scale: .longestEdge,
            longestEdge: 600
        )
        #expect(result == CGSize(width: 300, height: 600))
    }

    /// Vergrößert wird nie. Ein Bild auf 4000 Pixel zu ziehen, das 800 hat,
    /// macht die Datei größer, ohne einen einzigen Bildpunkt hinzuzufügen.
    @Test
    func neverEnlarges() {
        let size = CGSize(width: 800, height: 600)
        let result = ImageConversion.targetSize(for: size, scale: .longestEdge, longestEdge: 4000)
        #expect(result == size)
    }

    /// Ein sehr schmales Bild darf nicht auf null Pixel schrumpfen — das ließe
    /// sich nicht kodieren.
    @Test
    func neverShrinksBelowOnePixel() {
        let result = ImageConversion.targetSize(
            for: CGSize(width: 2000, height: 3),
            scale: .longestEdge,
            longestEdge: 100
        )
        #expect(result.height >= 1)
        #expect(result.width == 100)
    }

    @Test
    func aDegenerateSizeIsHandedBackUnchanged() {
        let empty = CGSize(width: 0, height: 0)
        #expect(ImageConversion.targetSize(for: empty, scale: .half, longestEdge: 100) == empty)
    }

    // MARK: - Umwandeln

    @Test
    func writesTheRequestedFormat() throws {
        let source = image(width: 64, height: 48)

        let png = try ImageConversion.convert(source, to: .png)
        #expect(png.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))

        let jpeg = try ImageConversion.convert(source, to: .jpeg)
        #expect(jpeg.data.starts(with: [0xFF, 0xD8, 0xFF]))
    }

    @Test
    func scalingChangesThePixelSize() throws {
        let output = try ImageConversion.convert(
            image(width: 400, height: 200),
            to: .png,
            scale: .half
        )
        #expect(output.pixelSize == CGSize(width: 200, height: 100))
    }

    /// Der Regler muss etwas bewirken, sonst ist er Dekoration.
    @Test
    func lowerQualityMakesASmallerFile() throws {
        let source = image(width: 400, height: 300)
        let good = try ImageConversion.convert(source, to: .jpeg, quality: 0.95)
        let poor = try ImageConversion.convert(source, to: .jpeg, quality: 0.3)
        #expect(poor.byteCount < good.byteCount)
    }

    /// Bei PNG bewirkt er nichts — deshalb wird er dort auch nicht angeboten.
    @Test
    func qualityDoesNothingForLosslessFormats() throws {
        #expect(!ImageConversion.Format.png.isLossy)
        #expect(!ImageConversion.Format.tiff.isLossy)
        #expect(ImageConversion.Format.jpeg.isLossy)
        #expect(ImageConversion.Format.heic.isLossy)
    }

    // MARK: - Stapel

    /// Der Punkt eines Stapels: Eine kaputte Datei darf die anderen
    /// neunundzwanzig nicht mitnehmen. Alles andere wäre eine Zumutung —
    /// einmal scheitern, alles noch einmal.
    @Test
    func oneBadFileDoesNotStopTheBatch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "anvil-batch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let good = directory.appending(path: "gut.png")
        try ImageConversion.convert(image(width: 40, height: 30), to: .png).data.write(to: good)

        let broken = directory.appending(path: "kaputt.png")
        try Data("das ist kein Bild".utf8).write(to: broken)

        let results = ImageConversion.convertAll([good, broken, good], to: .jpeg)

        #expect(results.count == 3)
        #expect(results[0].succeeded)
        #expect(!results[1].succeeded)
        #expect(results[1].failure != nil)
        #expect(results[2].succeeded)
    }

    /// Der Fortschritt muss vollständig zählen — ein Balken, der bei 2 von 3
    /// stehenbleibt, sieht aus wie ein Absturz.
    @Test
    func progressCountsEveryFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "anvil-batch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "bild.png")
        try ImageConversion.convert(image(width: 20, height: 20), to: .png).data.write(to: url)

        let seen = Reported()
        _ = ImageConversion.convertAll(
            [url, url, url],
            to: .png,
            onProgress: { done, total in seen.add(done, total) }
        )

        #expect(seen.steps == [(1, 3), (2, 3), (3, 3)].map { "\($0.0)/\($0.1)" })
    }

    /// Ein Stapel aus einer Datei, die es nicht gibt, ist kein Absturz —
    /// sondern ein Ergebnis mit einem Fehler darin.
    @Test
    func aMissingFileBecomesAFailedEntry() {
        let results = ImageConversion.convertAll(
            [URL(filePath: "/gibt/es/nicht/bild.png")],
            to: .png
        )
        #expect(results.count == 1)
        #expect(!results[0].succeeded)
    }

    /// Sammelt, was der Fortschritt meldet — über Threads hinweg.
    private final class Reported: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []

        func add(_ done: Int, _ total: Int) {
            lock.lock(); values.append("\(done)/\(total)"); lock.unlock()
        }

        var steps: [String] {
            lock.lock(); defer { lock.unlock() }
            return values
        }
    }

    // MARK: - Metadaten

    /// Der stillste und wichtigste Teil: Was hineingeht, darf nicht
    /// herauskommen. Ein Bild mit Koordinaten wird umgewandelt, und danach
    /// sind sie weg — nicht, weil ein Schalter das sagt, sondern weil neu
    /// gezeichnet und neu kodiert wird.
    @Test
    func conversionLeavesLocationAndCameraBehind() throws {
        let withMetadata = try #require(makeJPEGWithMetadata())

        let before = ImageConversion.metadataSummary(of: withMetadata)
        #expect(before.contains(localized("Aufnahmeort")))
        #expect(before.contains(localized("Kamera")))

        let source = try #require(NSImage(data: withMetadata))
        let converted = try ImageConversion.convert(source, to: .jpeg)

        let after = ImageConversion.metadataSummary(of: converted.data)
        #expect(after.isEmpty, "Nach dem Umwandeln steckt noch \(after) im Bild")
    }

    @Test
    func aPlainImageHasNothingToReport() throws {
        let plain = try ImageConversion.convert(image(width: 32, height: 32), to: .png)
        #expect(ImageConversion.metadataSummary(of: plain.data).isEmpty)
    }

    /// Baut ein JPEG mit Aufnahmeort und Kameramodell — die Vorlage für den
    /// Test darüber.
    private func makeJPEGWithMetadata() -> Data? {
        guard let base = image(width: 40, height: 30).tiffRepresentation,
              let source = CGImageSourceCreateWithData(base as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 48.137,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 11.575,
                kCGImagePropertyGPSLongitudeRef: "E"
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFModel: "Anvil Testkamera"
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:08:07 12:00:00"
            ]
        ]

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
