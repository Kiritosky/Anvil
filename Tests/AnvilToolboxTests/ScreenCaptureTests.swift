import AnvilKit
import AppKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("ScreenCapture")
struct ScreenCaptureTests {
    private let destination = URL(filePath: "/tmp/anvil-test.png")

    private func arguments(_ options: ScreenCapture.Options) -> [String] {
        ScreenCapture.arguments(for: options, destination: destination)
    }

    @Test
    func aRegionShotIsInteractive() {
        let result = arguments(ScreenCapture.Options(target: .region))
        #expect(result.contains("-i"))
        #expect(!result.contains("-w"))
    }

    @Test
    func aWindowShotClicksAWindow() {
        #expect(arguments(ScreenCapture.Options(target: .window)).contains("-w"))
    }

    @Test
    func aFullScreenShotNamesOneDisplay() {
        // With one file name and two screens, screencapture writes two files —
        // so the display is always spelled out.
        let result = arguments(ScreenCapture.Options(target: .fullScreen, displayIndex: 2))
        #expect(result.contains("-D"))
        #expect(result.contains("2"))
    }

    @Test
    func theDisplayNeverDropsBelowOne() {
        let result = arguments(ScreenCapture.Options(target: .fullScreen, displayIndex: 0))
        let index = result.firstIndex(of: "-D").map { result.index(after: $0) }
        #expect(index.map { result[$0] } == "1")
    }

    @Test
    func alwaysWritesPNGToTheGivenPath() {
        let result = arguments(ScreenCapture.Options(target: .region))
        #expect(result.contains("-t"))
        #expect(result.contains("png"))
        #expect(result.last == destination.path(percentEncoded: false))
    }

    @Test
    func theSoundIsSilencedByAskingForIt() {
        #expect(!arguments(ScreenCapture.Options(playsSound: true)).contains("-x"))
        #expect(arguments(ScreenCapture.Options(playsSound: false)).contains("-x"))
    }

    @Test
    func theCursorIsLeftOutUnlessAskedFor() {
        #expect(!arguments(ScreenCapture.Options(includesCursor: false)).contains("-C"))
        #expect(arguments(ScreenCapture.Options(includesCursor: true)).contains("-C"))
    }

    @Test
    func theWindowShadowIsDroppedByDefault() {
        #expect(arguments(ScreenCapture.Options(includesShadow: false)).contains("-o"))
        #expect(!arguments(ScreenCapture.Options(includesShadow: true)).contains("-o"))
    }

    @Test
    func aDelayOnlyAppliesToAShotNobodyHasToAimFirst() {
        let interactive = arguments(ScreenCapture.Options(target: .region, delay: 5))
        #expect(!interactive.contains("-T"), "die Verzögerung liefe vor dem Fadenkreuz")

        let immediate = arguments(ScreenCapture.Options(target: .fullScreen, delay: 5))
        #expect(immediate.contains("-T"))
        #expect(immediate.contains("5"))
    }

    @Test
    func onlyTheFullScreenShotIsTakenWithoutAiming() {
        #expect(ScreenCapture.Target.region.isInteractive)
        #expect(ScreenCapture.Target.window.isInteractive)
        #expect(!ScreenCapture.Target.fullScreen.isInteractive)
    }

    @Test
    func everyTargetDescribesItself() {
        for target in ScreenCapture.Target.allCases {
            #expect(!target.title.isEmpty)
            #expect(!target.explanation.isEmpty)
            #expect(!target.systemImage.isEmpty)
        }
    }
}

@MainActor
@Suite("ScreenshotController")
struct ScreenshotControllerTests {
    private func makeController(limit: Int = 20) -> (ScreenshotController, ToolContext) {
        let settings = SettingsStore.ephemeral()
        settings[.screenshotSessionLimit] = limit
        let context = ToolContext(
            settings: settings,
            history: HistoryStore(limit: 10),
            pasteboard: RecordingPasteboard()
        )
        return (ScreenshotController(context: context), context)
    }

    private func shot(_ target: ScreenCapture.Target = .region, text: String? = nil) -> Screenshot {
        Screenshot(image: NSImage(size: NSSize(width: 10, height: 10)), target: target, text: text)
    }

    @Test
    func theNewestShotIsTheSelectedOne() {
        let (controller, _) = makeController()
        controller.add(shot())
        let second = shot(.window)
        controller.add(second)

        #expect(controller.shots.count == 2)
        #expect(controller.selected?.id == second.id)
    }

    @Test
    func theSessionListStopsGrowing() {
        let (controller, _) = makeController(limit: 5)
        for _ in 0..<12 { controller.add(shot()) }
        #expect(controller.shots.count == 5)
    }

    @Test
    func theLimitNeverGoesBelowAHandful() {
        let (controller, _) = makeController(limit: 1)
        for _ in 0..<12 { controller.add(shot()) }
        #expect(controller.shots.count == 5)
    }

    @Test
    func removingTheSelectedShotSelectsAnother() {
        let (controller, _) = makeController()
        let first = shot()
        controller.add(first)
        let second = shot()
        controller.add(second)

        controller.remove(second)
        #expect(controller.selected?.id == first.id)
        #expect(controller.shots.count == 1)
    }

    @Test
    func clearingLeavesNothingSelected() {
        let (controller, _) = makeController()
        controller.add(shot())
        controller.clear()

        #expect(controller.shots.isEmpty)
        #expect(controller.selected == nil)
    }

    @Test
    func copyingTextOnlyCopiesWhenThereIsSome() {
        let (controller, context) = makeController()
        let pasteboard = context.pasteboard as? RecordingPasteboard

        controller.copyText(shot(text: nil))
        #expect(pasteboard?.copied.isEmpty == true)

        controller.copyText(shot(text: "Hallo"))
        #expect(pasteboard?.copied == ["Hallo"])
    }

    @Test
    func aPixelSizeIsReportedEvenWithoutRepresentations() {
        let empty = Screenshot(image: NSImage(size: NSSize(width: 40, height: 20)), target: .region)
        #expect(empty.pixelSize.width == 40)
    }
}
