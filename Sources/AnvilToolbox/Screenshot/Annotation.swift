import AnvilKit
import AppKit
import Foundation

/// A mark drawn on top of a screenshot.
///
/// Coordinates are normalised to 0…1 of the image, not points on screen. That
/// is what lets a mark survive the window being resized, the shot being shown
/// at half size, and the export being rendered at full resolution — all three
/// happen, and all three would otherwise move the arrow.
public struct Annotation: Identifiable, Sendable, Hashable, Codable {
    public enum Kind: String, Codable, CaseIterable, Sendable, Identifiable {
        case arrow
        case rectangle
        case ellipse
        case line
        /// Translucent fill — draws attention without hiding what is under it.
        case highlight
        /// Opaque fill. For things nobody else may read.
        case redact

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .arrow: localized("Pfeil")
            case .rectangle: localized("Rahmen")
            case .ellipse: localized("Ellipse")
            case .line: localized("Linie")
            case .highlight: localized("Markieren")
            case .redact: localized("Schwärzen")
            }
        }

        public var systemImage: String {
            switch self {
            case .arrow: "arrow.up.right"
            case .rectangle: "rectangle"
            case .ellipse: "oval"
            case .line: "line.diagonal"
            case .highlight: "highlighter"
            case .redact: "rectangle.fill"
            }
        }

        public var explanation: String {
            switch self {
            case .arrow: localized("Zeigt auf die Stelle, um die es geht.")
            case .rectangle: localized("Rahmt einen Bereich ein.")
            case .ellipse: localized("Kreist etwas ein.")
            case .line: localized("Eine gerade Linie.")
            case .highlight: localized("Durchscheinende Fläche, wie ein Textmarker.")
            case .redact:
                localized("Deckt endgültig ab. Kein Weichzeichner — der lässt sich zurückrechnen, eine Fläche nicht.")
            }
        }

        /// Whether the shape is filled rather than stroked.
        var isFilled: Bool {
            self == .highlight || self == .redact
        }
    }

    public var id: UUID
    public var kind: Kind
    /// Where the drag started, 0…1 of the image.
    public var start: CGPoint
    /// Where it ended.
    public var end: CGPoint
    public var color: ColorValue
    /// Stroke width in points at the image's own scale.
    public var lineWidth: CGFloat

    public init(
        id: UUID = UUID(),
        kind: Kind,
        start: CGPoint,
        end: CGPoint,
        color: ColorValue = ColorValue(red255: 255, green255: 59, blue255: 48),
        lineWidth: CGFloat = 4
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.color = color
        self.lineWidth = lineWidth
    }

    /// The rectangle the two corners describe, normalised, always positive.
    public var normalizedRect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    /// A drag too short to have been meant — a click, not a mark.
    public var isDegenerate: Bool {
        let rect = normalizedRect
        if kind == .arrow || kind == .line {
            return hypot(end.x - start.x, end.y - start.y) < 0.01
        }
        return rect.width < 0.005 || rect.height < 0.005
    }
}

/// Draws annotations onto an image.
public enum AnnotationRenderer {
    /// Returns a new image with the marks burned in.
    ///
    /// A copy, never in place: the original is what an undo goes back to, and
    /// what a second export starts from.
    @MainActor
    public static func render(_ image: NSImage, annotations: [Annotation]) -> NSImage {
        guard !annotations.isEmpty else { return image }

        let size = pixelSize(of: image)
        let result = NSImage(size: size)

        result.lockFocus()
        defer { result.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size))

        for annotation in annotations {
            draw(annotation, in: size)
        }

        return result
    }

    /// The image's real resolution, so a Retina shot is not exported at half
    /// its size.
    static func pixelSize(of image: NSImage) -> NSSize {
        guard let representation = image.representations.first,
              representation.pixelsWide > 0, representation.pixelsHigh > 0
        else { return image.size }
        return NSSize(width: representation.pixelsWide, height: representation.pixelsHigh)
    }

    @MainActor
    private static func draw(_ annotation: Annotation, in size: NSSize) {
        let color = NSColor(
            srgbRed: annotation.color.red,
            green: annotation.color.green,
            blue: annotation.color.blue,
            alpha: annotation.kind == .highlight ? 0.35 : 1
        )
        color.set()

        // Normalised coordinates count from the top down, the way a drag does;
        // AppKit draws from the bottom up.
        func point(_ normalized: CGPoint) -> NSPoint {
            NSPoint(x: normalized.x * size.width, y: (1 - normalized.y) * size.height)
        }

        let rect = annotation.normalizedRect
        let drawRect = NSRect(
            x: rect.minX * size.width,
            y: (1 - rect.maxY) * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
        // The stroke is stored at a nominal width; scale it with the image so a
        // 4pt line looks the same on a 5K shot as on a small one.
        let width = annotation.lineWidth * max(1, size.width / 1_200)

        switch annotation.kind {
        case .rectangle:
            let path = NSBezierPath(rect: drawRect)
            path.lineWidth = width
            path.stroke()
        case .ellipse:
            let path = NSBezierPath(ovalIn: drawRect)
            path.lineWidth = width
            path.stroke()
        case .highlight, .redact:
            NSBezierPath(rect: drawRect).fill()
        case .line:
            let path = NSBezierPath()
            path.move(to: point(annotation.start))
            path.line(to: point(annotation.end))
            path.lineWidth = width
            path.lineCapStyle = .round
            path.stroke()
        case .arrow:
            drawArrow(
                from: point(annotation.start),
                to: point(annotation.end),
                width: width
            )
        }
    }

    @MainActor
    private static func drawArrow(from start: NSPoint, to end: NSPoint, width: CGFloat) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(width * 4, 12)

        // The shaft stops short of the tip so the head is not drawn over a
        // line sticking out the front of it.
        let shaftEnd = NSPoint(
            x: end.x - cos(angle) * headLength * 0.8,
            y: end.y - sin(angle) * headLength * 0.8
        )

        let shaft = NSBezierPath()
        shaft.move(to: start)
        shaft.line(to: shaftEnd)
        shaft.lineWidth = width
        shaft.lineCapStyle = .round
        shaft.stroke()

        let spread = CGFloat.pi / 7
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: NSPoint(
            x: end.x - cos(angle - spread) * headLength,
            y: end.y - sin(angle - spread) * headLength
        ))
        head.line(to: NSPoint(
            x: end.x - cos(angle + spread) * headLength,
            y: end.y - sin(angle + spread) * headLength
        ))
        head.close()
        head.fill()
    }

    /// Where an image ends up inside a container that fits it, keeping the
    /// aspect ratio.
    ///
    /// Needed to turn a drag in the view into a point on the image: the picture
    /// almost never fills its pane, and the letterbox around it is not part of
    /// the shot.
    public static func fittedRect(for imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0
        else { return .zero }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Turns a point in the view into a point on the image, 0…1, or `nil` when
    /// the drag was outside the picture.
    public static func normalize(
        _ point: CGPoint,
        imageSize: CGSize,
        containerSize: CGSize
    ) -> CGPoint? {
        let frame = fittedRect(for: imageSize, in: containerSize)
        guard frame.width > 0, frame.height > 0 else { return nil }

        let normalized = CGPoint(
            x: (point.x - frame.minX) / frame.width,
            y: (point.y - frame.minY) / frame.height
        )
        guard (0...1).contains(normalized.x), (0...1).contains(normalized.y) else { return nil }
        return normalized
    }
}
