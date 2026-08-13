import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Den Satz App-Symbole bilden")
struct IconSetTests {
    @Test
    func macOSHasTheTenEntriesXcodeWants() {
        let items = IconSet.items(for: .macOS)
        #expect(items.count == 10)
        #expect(items.allSatisfy { $0.idiom == "mac" })
        #expect(items.map(\.pixels) == [16, 32, 32, 64, 128, 256, 256, 512, 512, 1024])
    }

    @Test
    func iOSCarriesTheStoreSizeAlong() {
        let items = IconSet.items(for: .iOS)
        #expect(items.count == 17)
        #expect(items.contains { $0.idiom == "ios-marketing" && $0.pixels == 1024 })
        #expect(items.contains { $0.idiom == "iphone" })
        #expect(items.contains { $0.idiom == "ipad" })
    }

    /// Die iPad-Größe mit Komma ist die eine, an der eine Rechnung mit
    /// ganzen Zahlen scheitern würde.
    @Test
    func theSizeWithADecimalPointSurvives() throws {
        let item = try #require(IconSet.iOSItems.first { $0.points == 83.5 })
        #expect(item.sizeText == "83.5x83.5")
        #expect(item.pixels == 167)
        #expect(item.fileName == "icon_ipad_83.5x83.5@2x.png")
    }

    @Test
    func namesFollowTheUsualSpelling() {
        let single = IconSet.Item(idiom: "mac", points: 16, scale: 1)
        let double = IconSet.Item(idiom: "mac", points: 16, scale: 2)
        #expect(single.fileName == "icon_16x16.png")
        #expect(double.fileName == "icon_16x16@2x.png")
        #expect(single.scaleText == "1x")
        #expect(double.pixels == 32)
    }

    /// Weniger zeichnen als schreiben: `32x32@1x` und `16x16@2x` sind
    /// dieselben zweiunddreißig Bildpunkte.
    @Test
    func everyPixelSizeIsDrawnOnlyOnce() {
        let sizes = IconSet.pixelSizes(for: .macOS)
        #expect(sizes == [16, 32, 64, 128, 256, 512, 1024])
        #expect(sizes.count < IconSet.items(for: .macOS).count)
        #expect(Set(sizes).count == sizes.count)
    }

    @Test
    func theLargestSizeIsTheOneToAskFor() {
        #expect(IconSet.largestPixelSize(for: .macOS) == 1024)
        #expect(IconSet.largestPixelSize(for: .iOS) == 1024)
    }

    /// iPhone und iPad verlangen dieselbe Größe in derselben Auflösung. Ohne
    /// das Gerät im Namen überschriebe die zweite Datei die erste.
    @Test
    func theSameSizeOnTwoDevicesGetsTwoNames() throws {
        let phone = try #require(
            IconSet.iOSItems.first { $0.idiom == "iphone" && $0.points == 20 && $0.scale == 2 }
        )
        let pad = try #require(
            IconSet.iOSItems.first { $0.idiom == "ipad" && $0.points == 20 && $0.scale == 2 }
        )
        #expect(phone.pixels == pad.pixels)
        #expect(phone.fileName != pad.fileName)
        #expect(phone.fileName == "icon_iphone_20x20@2x.png")
    }

    @Test
    func everyEntryHasItsOwnName() {
        for platform in IconSet.Platform.allCases {
            let names = IconSet.items(for: platform).map(\.fileName)
            #expect(Set(names).count == names.count)
            let ids = IconSet.items(for: platform).map(\.id)
            #expect(Set(ids).count == ids.count)
        }
    }

    // MARK: - Contents.json

    @Test
    func theContentsFileIsValidJSON() throws {
        for platform in IconSet.Platform.allCases {
            let data = Data(IconSet.contentsJSON(for: platform).utf8)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let images = try #require(object?["images"] as? [[String: String]])
            #expect(images.count == IconSet.items(for: platform).count)

            let info = try #require(object?["info"] as? [String: Any])
            #expect(info["author"] as? String == "xcode")
            #expect(info["version"] as? Int == 1)
        }
    }

    @Test
    func everyImageEntryCarriesTheFourFieldsXcodeReads() throws {
        let data = Data(IconSet.contentsJSON(for: .macOS).utf8)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let images = try #require(object?["images"] as? [[String: String]])
        let first = try #require(images.first)

        #expect(first["filename"] == "icon_16x16.png")
        #expect(first["idiom"] == "mac")
        #expect(first["scale"] == "1x")
        #expect(first["size"] == "16x16")
        #expect(images.allSatisfy { $0.keys.count == 4 })
    }

    @Test
    func theTableHasALinePerEntry() {
        for platform in IconSet.Platform.allCases {
            let rows = IconSet.rows(for: platform)
            #expect(rows.count == IconSet.items(for: platform).count)
            #expect(rows.allSatisfy { $0.count == IconSet.reportColumns.count })
        }
    }

    @Test
    func theFolderIsNamedAsXcodeExpects() {
        #expect(IconSet.folderName == "AppIcon.appiconset")
    }
}
