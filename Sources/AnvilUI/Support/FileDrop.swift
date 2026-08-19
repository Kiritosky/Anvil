import AnvilKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Was aus einem Drop herauskam.
public enum DroppedFile: Sendable {
    /// Text — aus einer Datei oder direkt aus der anderen App gezogen.
    /// Die URL fehlt, wenn nie eine Datei im Spiel war.
    case text(String, url: URL?)
    case image(NSImage, url: URL?)
    /// Die Datei selbst, ununtersucht — für Werkzeuge, die über die Bytes
    /// arbeiten statt über deren Bedeutung.
    case file(URL)

    public var url: URL? {
        switch self {
        case let .text(_, url): url
        case let .image(_, url): url
        case let .file(url): url
        }
    }
}

/// Was ein Ziel annimmt.
public struct FileDropKind: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let text = FileDropKind(rawValue: 1 << 0)
    public static let image = FileDropKind(rawValue: 1 << 1)
    /// Jede Datei, unabhängig vom Inhalt. Wer das verlangt, will die Bytes —
    /// eine Prüfsumme etwa — und nicht den entzifferten Text.
    public static let file = FileDropKind(rawValue: 1 << 2)
    public static let any: FileDropKind = [.text, .image]

    var typeIdentifiers: [UTType] {
        var types: [UTType] = [.fileURL]
        if contains(.text) { types.append(contentsOf: [.plainText, .utf8PlainText]) }
        if contains(.image) { types.append(.image) }
        return types
    }
}

extension View {
    /// Nimmt gezogene Dateien entgegen.
    public func anvilFileDrop(
        _ kinds: FileDropKind = .any,
        error: Binding<AnvilError?>? = nil,
        perform action: @escaping @MainActor (DroppedFile) -> Void
    ) -> some View {
        modifier(FileDropModifier(kinds: kinds, error: error) { files in
            guard let first = files.first else { return }
            action(first)
        })
    }

    /// Dasselbe, aber für alle gezogenen Dateien auf einmal.
    public func anvilFilesDrop(
        _ kinds: FileDropKind = .any,
        error: Binding<AnvilError?>? = nil,
        perform action: @escaping @MainActor ([DroppedFile]) -> Void
    ) -> some View {
        modifier(FileDropModifier(kinds: kinds, error: error, action: action))
    }
}

private struct FileDropModifier: ViewModifier {
    let kinds: FileDropKind
    let error: Binding<AnvilError?>?
    let action: @MainActor ([DroppedFile]) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                    .strokeBorder(AnvilColor.accent, lineWidth: AnvilSize.focusRing)
                    .opacity(isTargeted ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(AnvilMotion.quick, value: isTargeted)
            .onDrop(of: kinds.typeIdentifiers, isTargeted: $isTargeted) { providers in
                guard !providers.isEmpty else { return false }
                FileDropReader.readAll(providers, kinds: kinds) { files, failure in
                    if files.isEmpty, let failure { error?.wrappedValue = failure }
                    if !files.isEmpty { action(files) }
                }
                return true
            }
    }
}

/// Holt aus einem Drop das heraus, was ein Werkzeug damit anfangen kann.
enum FileDropReader {
    /// Liest alle Anbieter und ruft den Empfänger einmal, wenn der letzte
    /// fertig ist.
    @MainActor
    static func readAll(
        _ providers: [NSItemProvider],
        kinds: FileDropKind,
        completion: @escaping @MainActor ([DroppedFile], AnvilError?) -> Void
    ) {
        var slots = [DroppedFile?](repeating: nil, count: providers.count)
        var firstFailure: AnvilError?
        var remaining = providers.count

        for (index, provider) in providers.enumerated() {
            read(provider, kinds: kinds) { result in
                switch result {
                case let .success(file): slots[index] = file
                case let .failure(failure): firstFailure = firstFailure ?? failure
                }

                remaining -= 1
                guard remaining == 0 else { return }
                completion(slots.compactMap { $0 }, firstFailure)
            }
        }
    }

    static func read(
        _ provider: NSItemProvider,
        kinds: FileDropKind,
        completion: @escaping @MainActor (Result<DroppedFile, AnvilError>) -> Void
    ) {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in
                    guard let url else {
                        completion(.failure(.invalidInput(
                            localized("Das Gezogene ließ sich nicht lesen.")
                        )))
                        return
                    }
                    completion(load(url, kinds: kinds))
                }
            }
            return
        }

        if kinds.contains(.image), provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                let image = object as? NSImage
                Task { @MainActor in
                    guard let image else {
                        completion(.failure(.invalidInput(
                            localized("Das gezogene Bild ließ sich nicht lesen.")
                        )))
                        return
                    }
                    completion(.success(.image(image, url: nil)))
                }
            }
            return
        }

        if kinds.contains(.text), provider.canLoadObject(ofClass: String.self) {
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                Task { @MainActor in
                    guard let text else {
                        completion(.failure(.invalidInput(
                            localized("Der gezogene Text ließ sich nicht lesen.")
                        )))
                        return
                    }
                    completion(.success(.text(text, url: nil)))
                }
            }
            return
        }

        Task { @MainActor in
            completion(.failure(.invalidInput(rejection(for: kinds))))
        }
    }

    /// Lädt eine Datei — und sagt, wenn sie nicht passt.
    @MainActor
    static func load(_ url: URL, kinds: FileDropKind) -> Result<DroppedFile, AnvilError> {
        let type = UTType(filenameExtension: url.pathExtension)

        if kinds == .file {
            return .success(.file(url))
        }

        if isDirectory(url) {
            return .success(.file(url))
        }

        if kinds.contains(.image), type?.conforms(to: .image) == true {
            guard let image = NSImage(contentsOf: url) else {
                return .failure(.invalidInput(
                    localized("„\(url.lastPathComponent)\" ließ sich nicht als Bild öffnen.")
                ))
            }
            return .success(.image(image, url: url))
        }

        if kinds.contains(.text) {
            do {
                return .success(.text(try TextFile.read(at: url), url: url))
            } catch {
                return .failure(AnvilError.wrapping(error))
            }
        }

        if kinds.contains(.file) {
            return .success(.file(url))
        }

        return .failure(.invalidInput(rejection(for: kinds)))
    }

    /// Ob der Pfad auf einen Ordner zeigt.
    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// Was das Ziel überhaupt genommen hätte.
    private static func rejection(for kinds: FileDropKind) -> String {
        if kinds == .file {
            return localized("Hier geht eine Datei hinein — gezogener Text ist keine.")
        }
        if kinds == .any {
            return localized("Damit kann dieses Werkzeug nichts anfangen — Textdateien und Bilder gehen.")
        }
        if kinds.contains(.image) {
            return localized("Hier gehen nur Bilder hinein.")
        }
        return localized("Hier gehen nur Textdateien hinein.")
    }
}
