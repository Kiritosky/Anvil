import AnvilKit
import AppKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("QRCode")
struct QRCodeTests {
    @Test
    func rendersAtTheRequestedSize() throws {
        let image = try QRCode.image(for: "https://anvil.dev", size: 256)
        #expect(image.size.width == 256)
        #expect(image.size.height == 256)
    }

    @Test
    func refusesEmptyInput() {
        #expect(throws: AnvilError.self) {
            try QRCode.image(for: "   ")
        }
    }

    @Test
    func readsBackWhatItWrote() throws {
        let message = "Anvil — Werkzeugkasten"
        let image = try QRCode.image(for: message, correction: .high, size: 512)
        #expect(QRCode.read(image).contains(message))
    }

    @Test
    func survivesTheHighestCorrectionLevel() throws {
        for correction in QRCode.Correction.allCases {
            let image = try QRCode.image(for: "Test", correction: correction, size: 128)
            #expect(image.size.width == 128)
        }
    }

    @Test
    func findsNothingInABlankImage() {
        let blank = NSImage(size: NSSize(width: 64, height: 64))
        #expect(QRCode.read(blank).isEmpty)
    }
}
