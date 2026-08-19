import AnvilKit
import AppKit
import SwiftUI

/// Was beim Herausziehen entsteht.
public enum DragOutContent {
    /// Ein Bild. Geht als PNG heraus — das versteht jedes Ziel.
    case image(NSImage)
    /// Text. Geht als Datei heraus, damit auch der Finder etwas damit
    /// anfangen kann; Programme, die lieber Text hätten, holen ihn sich aus
    /// derselben Datei.
    case text(String, extension: String)

    var pathExtension: String {
        switch self {
        case .image: "png"
        case let .text(_, pathExtension): pathExtension
        }
    }

    func data() throws -> Data {
        switch self {
        case let .image(image): try image.pngData()
        case let .text(text, _): Data(text.utf8)
        }
    }
}

extension View {
    /// Macht diese Ansicht zu etwas, das man in den Finder ziehen kann.
    public func anvilDragOut(
        name: @escaping @autoclosure () -> String,
        content: @escaping () -> DragOutContent?
    ) -> some View {
        onDrag {
            guard let content = content(),
                  let url = try? ExportFile.temporary(
                      named: name(),
                      extension: content.pathExtension,
                      contents: content.data()
                  ),
                  let provider = NSItemProvider(contentsOf: url)
            else {
                return NSItemProvider()
            }
            provider.suggestedName = url.lastPathComponent
            return provider
        }
    }
}
