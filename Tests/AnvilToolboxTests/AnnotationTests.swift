import AnvilKit
import AppKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Annotation")
struct AnnotationTests {
    private func mark(
        _ kind: Annotation.Kind = .rectangle,
        from start: CGPoint,
        to end: CGPoint
    ) -> Annotation {
        Annotation(kind: kind, start: start, end: end)
    }

    @Test
    func aRectangleIsPositiveWhicheverWayItWasDragged() {
        let downRight = mark(from: CGPoint(x: 0.2, y: 0.2), to: CGPoint(x: 0.8, y: 0.6))
        let upLeft = mark(from: CGPoint(x: 0.8, y: 0.6), to: CGPoint(x: 0.2, y: 0.2))

        #expect(downRight.normalizedRect == upLeft.normalizedRect)
        #expect(downRight.normalizedRect.width > 0)
        #expect(downRight.normalizedRect.height > 0)
    }

    @Test
    func aClickIsNotAMark() {
        let click = mark(from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.5005, y: 0.5005))
        #expect(click.isDegenerate)

        let drag = mark(from: CGPoint(x: 0.2, y: 0.2), to: CGPoint(x: 0.6, y: 0.6))
        #expect(!drag.isDegenerate)
    }

    @Test
    func aShortArrowIsJudgedByItsLengthNotItsBox() {
        // A perfectly diagonal arrow has a box, a horizontal one has none.
        let horizontal = mark(.arrow, from: CGPoint(x: 0.1, y: 0.5), to: CGPoint(x: 0.9, y: 0.5))
        #expect(!horizontal.isDegenerate)

        let stub = mark(.arrow, from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.503, y: 0.5))
        #expect(stub.isDegenerate)
    }

    @Test
    func filledKindsAreTheOnesThatHideThings() {
        #expect(Annotation.Kind.redact.isFilled)
        #expect(Annotation.Kind.highlight.isFilled)
        #expect(!Annotation.Kind.arrow.isFilled)
        #expect(!Annotation.Kind.rectangle.isFilled)
    }

    @Test
    func everyKindDescribesItself() {
        for kind in Annotation.Kind.allCases {
            #expect(!kind.title.isEmpty)
            #expect(!kind.explanation.isEmpty)
            #expect(!kind.systemImage.isEmpty)
        }
    }

    @Test
    func roundTripsThroughJSON() throws {
        let annotation = mark(.arrow, from: CGPoint(x: 0.1, y: 0.2), to: CGPoint(x: 0.3, y: 0.4))
        let data = try JSONEncoder().encode(annotation)
        #expect(try JSONDecoder().decode(Annotation.self, from: data) == annotation)
    }
}

@Suite("AnnotationRenderer")
struct AnnotationRendererTests {
    @Test
    func anImageFitsItsContainerAndStaysCentred() {
        // A wide image in a square pane: letterboxed top and bottom.
        let frame = AnnotationRenderer.fittedRect(
            for: CGSize(width: 200, height: 100),
            in: CGSize(width: 100, height: 100)
        )
        #expect(frame.width == 100)
        #expect(frame.height == 50)
        #expect(frame.minY == 25)
        #expect(frame.minX == 0)
    }

    @Test
    func atallImageIsPillarboxed() {
        let frame = AnnotationRenderer.fittedRect(
            for: CGSize(width: 100, height: 200),
            in: CGSize(width: 100, height: 100)
        )
        #expect(frame.height == 100)
        #expect(frame.width == 50)
        #expect(frame.minX == 25)
    }

    @Test
    func anEmptyContainerHasNoFrame() {
        #expect(AnnotationRenderer.fittedRect(for: .zero, in: CGSize(width: 10, height: 10)) == .zero)
        #expect(AnnotationRenderer.fittedRect(for: CGSize(width: 10, height: 10), in: .zero) == .zero)
    }

    @Test
    func aPointInTheMiddleIsTheMiddleOfTheImage() {
        let normalized = AnnotationRenderer.normalize(
            CGPoint(x: 50, y: 50),
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        )
        #expect(normalized?.x == 0.5)
        #expect(normalized?.y == 0.5)
    }

    @Test
    func aPointInTheLetterboxIsNotOnTheImage() {
        // The top 25 points of that pane are empty space, not picture.
        let normalized = AnnotationRenderer.normalize(
            CGPoint(x: 50, y: 5),
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        )
        #expect(normalized == nil)
    }

    @MainActor
    @Test
    func renderingWithoutMarksHandsBackTheSameImage() {
        let image = NSImage(size: NSSize(width: 20, height: 10))
        let result = AnnotationRenderer.render(image, annotations: [])
        #expect(result === image)
    }

    @MainActor
    @Test
    func renderingKeepsTheFullResolution() {
        let image = NSImage(size: NSSize(width: 40, height: 20))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 20).fill()
        image.unlockFocus()

        let marked = AnnotationRenderer.render(image, annotations: [
            Annotation(kind: .redact, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.5, y: 0.5))
        ])

        #expect(marked.size.width == AnnotationRenderer.pixelSize(of: image).width)
        #expect(marked !== image, "das Original bleibt unangetastet")
    }
}

@MainActor
@Suite("Screenshot annotieren")
struct ScreenshotAnnotationTests {
    private func makeController() -> ScreenshotController {
        ScreenshotController(
            context: ToolContext(
                settings: .ephemeral(),
                history: HistoryStore(limit: 5),
                pasteboard: RecordingPasteboard()
            )
        )
    }

    private var shot: Screenshot {
        Screenshot(image: NSImage(size: NSSize(width: 10, height: 10)), target: .region)
    }

    private var mark: Annotation {
        Annotation(kind: .arrow, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.8, y: 0.8))
    }

    @Test
    func aMarkLandsOnTheShot() {
        let controller = makeController()
        let shot = shot
        controller.add(shot)
        controller.add(mark, to: shot)

        #expect(controller.shots[0].annotations.count == 1)
        #expect(controller.shots[0].isAnnotated)
    }

    @Test
    func aStrayClickAddsNothing() {
        let controller = makeController()
        let shot = shot
        controller.add(shot)
        controller.add(
            Annotation(kind: .rectangle, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 0.5)),
            to: shot
        )

        #expect(controller.shots[0].annotations.isEmpty)
    }

    @Test
    func undoTakesBackTheLastOne() {
        let controller = makeController()
        let shot = shot
        controller.add(shot)
        controller.add(mark, to: shot)
        controller.add(mark, to: shot)
        controller.undoAnnotation(on: shot)

        #expect(controller.shots[0].annotations.count == 1)
    }

    @Test
    func undoOnAnUnmarkedShotDoesNothing() {
        let controller = makeController()
        let shot = shot
        controller.add(shot)
        controller.undoAnnotation(on: shot)

        #expect(controller.shots[0].annotations.isEmpty)
    }

    @Test
    func clearingRemovesEveryMark() {
        let controller = makeController()
        let shot = shot
        controller.add(shot)
        controller.add(mark, to: shot)
        controller.clearAnnotations(on: shot)

        #expect(controller.shots[0].annotations.isEmpty)
    }

    @Test
    func markingInvalidatesTheSavedFile() {
        // What is on disk no longer matches what is on screen.
        let controller = makeController()
        var shot = shot
        shot.fileURL = URL(filePath: "/tmp/alt.png")
        controller.add(shot)
        controller.add(mark, to: shot)

        #expect(controller.shots[0].fileURL == nil)
    }
}
