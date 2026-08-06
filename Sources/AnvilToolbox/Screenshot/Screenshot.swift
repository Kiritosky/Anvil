import AppKit
import Foundation

/// One shot taken in this session.
public struct Screenshot: Identifiable, Sendable {
    public let id: UUID
    public let image: NSImage
    /// Where it was kept, when it was kept.
    public var fileURL: URL?
    public let target: ScreenCapture.Target
    public let takenAt: Date
    /// Filled in when the text has been read out of it.
    public var text: String?
    /// Marks drawn on top. The picture itself is never touched — flattening
    /// happens on the way out, so an undo has something to go back to.
    public var annotations: [Annotation] = []

    public init(
        id: UUID = UUID(),
        image: NSImage,
        fileURL: URL? = nil,
        target: ScreenCapture.Target,
        takenAt: Date = .now,
        text: String? = nil,
        annotations: [Annotation] = []
    ) {
        self.id = id
        self.image = image
        self.fileURL = fileURL
        self.target = target
        self.takenAt = takenAt
        self.text = text
        self.annotations = annotations
    }

    public var isAnnotated: Bool { !annotations.isEmpty }

    /// The real resolution, not the point size — a Retina shot is twice as
    /// large as `image.size` claims, and that number is what the status bar
    /// reports.
    public var pixelSize: NSSize {
        guard let representation = image.representations.first else { return image.size }
        return NSSize(width: representation.pixelsWide, height: representation.pixelsHigh)
    }
}
