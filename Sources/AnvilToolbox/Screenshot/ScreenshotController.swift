import AnvilKit
import AppKit
import Foundation
import Observation

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

    public init(
        id: UUID = UUID(),
        image: NSImage,
        fileURL: URL? = nil,
        target: ScreenCapture.Target,
        takenAt: Date = .now,
        text: String? = nil
    ) {
        self.id = id
        self.image = image
        self.fileURL = fileURL
        self.target = target
        self.takenAt = takenAt
        self.text = text
    }

    public var pixelSize: NSSize {
        guard let representation = image.representations.first else { return image.size }
        return NSSize(width: representation.pixelsWide, height: representation.pixelsHigh)
    }
}

/// Taking screenshots, and what happens to them afterwards.
///
/// An app-level service rather than view state, for the same reason quick
/// dictation is one: the shortcut has to work while the tool is closed, and
/// what it produces has to still be there when the tool is opened.
@MainActor
@Observable
public final class ScreenshotController {
    public private(set) var shots: [Screenshot] = []
    public private(set) var isCapturing = false
    public var error: AnvilError?
    /// The shot the tool shows. Follows the newest one unless the user picks.
    public var selectedID: Screenshot.ID?

    @ObservationIgnored private let context: ToolContext

    /// Set by the app so a global shortcut can bring the window forward.
    @ObservationIgnored public var onCaptured: ((Screenshot) -> Void)?

    public init(context: ToolContext) {
        self.context = context
    }

    private var settings: SettingsStore { context.settings }

    // MARK: - Taking

    public func capture(_ target: ScreenCapture.Target) async {
        guard !isCapturing else { return }
        error = nil
        isCapturing = true
        defer { isCapturing = false }

        let options = ScreenCapture.Options(
            target: target,
            delay: settings[.screenshotDelay],
            includesCursor: settings[.screenshotIncludesCursor],
            includesShadow: settings[.screenshotIncludesShadow],
            playsSound: settings[.screenshotPlaysSound]
        )

        do {
            guard let url = try await ScreenCapture.capture(options),
                  let image = NSImage(contentsOf: url)
            else { return }

            var shot = Screenshot(image: image, target: target)

            if settings[.screenshotKeepsFile] {
                shot.fileURL = try? ScreenCapture.keep(url)
            }
            if settings[.screenshotCopiesImage] {
                copyImage(shot)
            }
            try? FileManager.default.removeItem(at: url)

            if settings[.screenshotReadsText] {
                shot.text = try? TextRecognizer.recognize(image).text
                if settings[.screenshotCopiesText], let text = shot.text, !text.isEmpty {
                    context.pasteboard.copy(text)
                }
            }

            add(shot)
            onCaptured?(shot)
        } catch {
            self.error = AnvilError.wrapping(error)
        }
    }

    /// Takes a shot and puts only its text on the clipboard — the shortcut for
    /// "I want what that dialog says, not a picture of it".
    public func captureText(_ target: ScreenCapture.Target = .region) async {
        error = nil
        isCapturing = true
        defer { isCapturing = false }

        do {
            let options = ScreenCapture.Options(
                target: target,
                includesCursor: false,
                includesShadow: false,
                playsSound: settings[.screenshotPlaysSound]
            )
            guard let url = try await ScreenCapture.capture(options),
                  let image = NSImage(contentsOf: url)
            else { return }
            try? FileManager.default.removeItem(at: url)

            let recognised = try TextRecognizer.recognize(image, mode: settings[.ocrMode])
            var shot = Screenshot(image: image, target: target, text: recognised.text)
            if settings[.screenshotKeepsFile] { shot.fileURL = nil }

            guard !recognised.isEmpty else {
                error = .invalidInput(localized("In der Aufnahme ist kein Text zu finden."))
                add(shot)
                return
            }

            context.pasteboard.copy(recognised.text)
            add(shot)
            onCaptured?(shot)
        } catch {
            self.error = AnvilError.wrapping(error)
        }
    }

    private func add(_ shot: Screenshot) {
        shots.insert(shot, at: 0)
        selectedID = shot.id

        // The session list is a working set, not an archive — what is worth
        // keeping is already on disk.
        let limit = max(5, settings[.screenshotSessionLimit])
        if shots.count > limit { shots.removeLast(shots.count - limit) }
    }

    // MARK: - Working with a shot

    public var selected: Screenshot? {
        guard let selectedID else { return shots.first }
        return shots.first { $0.id == selectedID } ?? shots.first
    }

    public func copyImage(_ shot: Screenshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([shot.image])
    }

    public func copyText(_ shot: Screenshot) {
        guard let text = shot.text, !text.isEmpty else { return }
        context.pasteboard.copy(text)
    }

    @discardableResult
    public func keep(_ shot: Screenshot) -> URL? {
        guard let index = shots.firstIndex(where: { $0.id == shot.id }) else { return nil }
        if let existing = shots[index].fileURL { return existing }

        do {
            let data = shot.image.tiffRepresentation
            guard let data, let bitmap = NSBitmapImageRep(data: data),
                  let png = bitmap.representation(using: .png, properties: [:])
            else {
                error = .storage(localized("Das Bild konnte nicht als PNG gesichert werden."))
                return nil
            }

            AppPaths.bootstrap()
            let stamp = ISO8601DateFormatter().string(from: shot.takenAt)
                .replacingOccurrences(of: ":", with: "-")
            let url = AppPaths.screenshots.appending(path: "Bildschirmfoto \(stamp).png")
            try png.write(to: url)

            shots[index].fileURL = url
            return url
        } catch {
            self.error = AnvilError.wrapping(error)
            return nil
        }
    }

    /// Reads the text out of a shot that was taken without recognition.
    public func readText(_ shot: Screenshot) {
        guard let index = shots.firstIndex(where: { $0.id == shot.id }) else { return }
        do {
            let recognised = try TextRecognizer.recognize(shot.image, mode: settings[.ocrMode])
            shots[index].text = recognised.text
        } catch {
            self.error = AnvilError.wrapping(error)
        }
    }

    public func reveal(_ shot: Screenshot) {
        guard let url = shot.fileURL ?? keep(shot) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func remove(_ shot: Screenshot) {
        shots.removeAll { $0.id == shot.id }
        if selectedID == shot.id { selectedID = shots.first?.id }
    }

    public func clear() {
        shots = []
        selectedID = nil
    }
}

// MARK: - Settings keys

extension SettingKey {
    public static var screenshotDelay: SettingKey<Int> {
        SettingKey<Int>("screenshot.delay", default: 0)
    }

    public static var screenshotIncludesCursor: SettingKey<Bool> {
        SettingKey<Bool>("screenshot.cursor", default: false)
    }

    public static var screenshotIncludesShadow: SettingKey<Bool> {
        SettingKey<Bool>("screenshot.shadow", default: false)
    }

    public static var screenshotPlaysSound: SettingKey<Bool> {
        SettingKey<Bool>("screenshot.sound", default: true)
    }

    /// Keep a PNG next to the app's other files. Off means the shot lives in
    /// this session only, which is what most screenshots deserve.
    public static var screenshotKeepsFile: SettingKey<Bool> {
        SettingKey<Bool>("screenshot.keepFile", default: false)
    }

    public static var screenshotCopiesImage: SettingKey<Bool> {
        SettingKey<Bool>("screenshot.copyImage", default: true)
    }

    public static var screenshotReadsText: SettingKey<Bool> {
        SettingKey<Bool>("screenshot.readText", default: false)
    }

    public static var screenshotCopiesText: SettingKey<Bool> {
        SettingKey<Bool>("screenshot.copyText", default: false)
    }

    public static var screenshotSessionLimit: SettingKey<Int> {
        SettingKey<Int>("screenshot.sessionLimit", default: 20)
    }
}

// MARK: - Tool context

extension ToolContext {
    /// Screenshots, registered by the app at launch.
    public var screenshots: ScreenshotController { require(ScreenshotController.self) }
}
