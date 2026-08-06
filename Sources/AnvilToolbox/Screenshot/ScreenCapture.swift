import AnvilKit
import AppKit
import Foundation

/// Taking pictures of the screen.
///
/// Built on the `screencapture` binary rather than ScreenCaptureKit, and that
/// is a deliberate choice: it brings the whole selection interaction — the
/// crosshair, space to switch to window mode, Escape to cancel, the shutter
/// sound, the flash — for free, it is what the system shortcuts themselves
/// use, and it needs no window of our own over the screen we are trying to
/// photograph. The permission prompt is the same one either way.
public enum ScreenCapture {
    /// What to photograph.
    public enum Target: String, Codable, CaseIterable, Sendable, Identifiable {
        /// Drag a rectangle. Space switches to window mode mid-drag.
        case region
        /// Click a window; it is captured without its background.
        case window
        /// Everything on every display.
        case fullScreen

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .region: localized("Ausschnitt")
            case .window: localized("Fenster")
            case .fullScreen: localized("Ganzer Bildschirm")
            }
        }

        public var systemImage: String {
            switch self {
            case .region: "rectangle.dashed"
            case .window: "macwindow"
            case .fullScreen: "menubar.dock.rectangle"
            }
        }

        public var explanation: String {
            switch self {
            case .region:
                localized("Rechteck aufziehen. Leertaste wechselt zum Fenstermodus, ⎋ bricht ab.")
            case .window:
                localized("Fenster anklicken. Wird ohne Hintergrund aufgenommen.")
            case .fullScreen:
                localized("Alle Bildschirme, sofort.")
            }
        }

        /// The flags `screencapture` needs for this target.
        var arguments: [String] {
            switch self {
            case .region: ["-i"]
            case .window: ["-w"]
            case .fullScreen: []
            }
        }

        /// Whether the user is asked to point at something. Interactive targets
        /// must not carry a delay — the delay would run before the crosshair.
        public var isInteractive: Bool {
            self != .fullScreen
        }
    }

    /// How the shot is taken.
    public struct Options: Sendable {
        public var target: Target
        /// Seconds to wait before a non-interactive shot. Time to arrange
        /// whatever is being photographed.
        public var delay: Int
        public var includesCursor: Bool
        /// A window shot normally comes with the drop shadow around it, which
        /// is dead space in a bug report.
        public var includesShadow: Bool
        public var playsSound: Bool

        public init(
            target: Target = .region,
            delay: Int = 0,
            includesCursor: Bool = false,
            includesShadow: Bool = false,
            playsSound: Bool = true
        ) {
            self.target = target
            self.delay = delay
            self.includesCursor = includesCursor
            self.includesShadow = includesShadow
            self.playsSound = playsSound
        }
    }

    /// Takes the shot and returns where it was written, or `nil` when the user
    /// cancelled.
    ///
    /// Always to a file first, never straight to the clipboard: the file is
    /// what makes "save it" and "copy it" and "read the text in it" the same
    /// code path afterwards.
    public static func capture(_ options: Options) async throws -> URL? {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "anvil-\(UUID().uuidString).png")

        var arguments = options.target.arguments + ["-t", "png"]
        if !options.playsSound { arguments.append("-x") }
        if options.includesCursor { arguments.append("-C") }
        if !options.includesShadow { arguments.append("-o") }
        if options.delay > 0, !options.target.isInteractive {
            arguments.append(contentsOf: ["-T", String(options.delay)])
        }
        arguments.append(destination.path(percentEncoded: false))

        let runner = ProcessRunner()
        // Ten minutes: the user decides how long they take to aim, and a
        // timeout that fires mid-selection would be worse than no timeout.
        let result = try await runner.run(
            "/usr/sbin/screencapture",
            arguments: arguments,
            timeout: 600
        )

        // Escape writes no file and still exits zero.
        guard FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
            guard result.succeeded else {
                throw AnvilError.storage(
                    localized("Der Bildschirm konnte nicht aufgenommen werden: \(result.standardError)")
                )
            }
            return nil
        }

        return destination
    }

    /// Moves a temporary shot into the folder screenshots are kept in.
    public static func keep(_ url: URL, at date: Date = .now) throws -> URL {
        AppPaths.bootstrap()

        let stamp = ISO8601DateFormatter().string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        let destination = AppPaths.screenshots.appending(path: "Bildschirmfoto \(stamp).png")

        do {
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            throw AnvilError.storage(
                localized("Das Bildschirmfoto konnte nicht gesichert werden: \(error.localizedDescription)")
            )
        }
        return destination
    }
}
