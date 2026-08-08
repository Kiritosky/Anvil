import AnvilKit
import AppKit
import Foundation
import Vision

/// Reading text out of pictures.
///
/// Vision does the recognising; the work here is everything around it — picking
/// a region of the screen, getting the languages right, and putting the lines
/// back together in an order a human would read them in. Vision returns
/// observations in no particular order, and a naive `joined()` produces a
/// jumble on anything with two columns.
public enum TextRecognizer {
    /// One recognised line, with where it sat on the page.
    public struct Line: Sendable, Identifiable, Hashable {
        public let id: Int
        public let text: String
        /// Normalised, origin bottom-left — Vision's coordinate space.
        public let box: CGRect
        /// 0…1, Vision's own estimate.
        public let confidence: Float

        public init(id: Int, text: String, box: CGRect, confidence: Float) {
            self.id = id
            self.text = text
            self.box = box
            self.confidence = confidence
        }
    }

    public struct Result: Sendable {
        public var lines: [Line]

        public var text: String {
            lines.map(\.text).joined(separator: "\n")
        }

        public var isEmpty: Bool { lines.isEmpty }

        /// Setzt den Text mehrerer Bilder zu einem zusammen.
        ///
        /// Bei einem Bild bleibt es der reine Text — man will ihn einfügen,
        /// nicht lesen, wo er herkommt. Ab zwei bekommt jeder Block den Namen
        /// seines Bildes davor: Ohne den weiß nach dem Einfügen niemand mehr,
        /// welcher Absatz aus welchem Screenshot stammt, und das ist genau
        /// der Fall, für den man mehrere auf einmal liest.
        ///
        /// Bilder ohne Text fallen nicht heraus, sondern bekommen ihren
        /// Hinweis. Eine Lücke, die man nicht sieht, hält man für Text, den es
        /// nicht gab.
        public static func combine(_ pieces: [(name: String, text: String)]) -> String {
            guard pieces.count != 1 else { return pieces[0].text }

            return pieces
                .map { piece in
                    let body = piece.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return body.isEmpty
                        ? "\(piece.name)\n\(localized("— kein Text —"))"
                        : "\(piece.name)\n\(body)"
                }
                .joined(separator: "\n\n")
        }

        /// The mean of Vision's per-line confidences.
        public var confidence: Float {
            guard !lines.isEmpty else { return 0 }
            return lines.map(\.confidence).reduce(0, +) / Float(lines.count)
        }
    }

    /// What Vision should be told to expect.
    public enum Mode: String, Codable, CaseIterable, Sendable, Identifiable {
        /// Ordinary prose. Language correction on.
        case prose
        /// Code, serial numbers, licence keys — anything where "l" must not
        /// become "1" because a dictionary said so.
        case exact

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .prose: localized("Fließtext")
            case .exact: localized("Zeichengenau")
            }
        }

        public var explanation: String {
            switch self {
            case .prose:
                localized("Korrigiert anhand des Wortschatzes — richtig für Sätze.")
            case .exact:
                localized("Keine Korrektur. Für Code, Schlüssel und Nummern, wo jedes Zeichen zählt.")
            }
        }
    }

    /// Recognises text in `image`.
    public static func recognize(
        _ image: NSImage,
        mode: Mode = .prose,
        languages: [String] = ["de-DE", "en-US"]
    ) throws -> Result {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AnvilError.invalidInput(localized("Aus diesem Bild lässt sich nichts lesen."))
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = mode == .prose
        request.recognitionLanguages = languages

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw AnvilError.wrapping(error)
        }

        let observations = request.results ?? []
        let lines = observations.enumerated().compactMap { index, observation -> Line? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return Line(
                id: index,
                text: candidate.string,
                box: observation.boundingBox,
                confidence: candidate.confidence
            )
        }

        return Result(lines: sortIntoReadingOrder(lines))
    }

    /// Sorts lines the way they are read: top to bottom, and within a band that
    /// shares a baseline, left to right.
    ///
    /// The tolerance is what makes two columns come out as two columns instead
    /// of alternating between them line by line.
    static func sortIntoReadingOrder(_ lines: [Line], tolerance: CGFloat = 0.012) -> [Line] {
        lines
            .sorted { first, second in
                // Vision's origin is bottom-left, so a larger y is higher up.
                if abs(first.box.midY - second.box.midY) > tolerance {
                    return first.box.midY > second.box.midY
                }
                return first.box.minX < second.box.minX
            }
            .enumerated()
            .map { index, line in
                Line(id: index, text: line.text, box: line.box, confidence: line.confidence)
            }
    }

    /// Lets the user drag a rectangle over the screen and returns what was in
    /// it, or `nil` when they pressed Escape.
    ///
    /// Uses the `screencapture` binary rather than ScreenCaptureKit: it brings
    /// the whole selection interaction — crosshair, window highlighting, space
    /// switching — for free, and it is the same code path the system shortcut
    /// uses. The first run asks for the Screen Recording permission.
    @MainActor
    public static func captureRegion() async throws -> NSImage? {
        let runner = ProcessRunner()
        let before = NSPasteboard.general.changeCount

        // No timeout worth the name: the user decides how long they take to
        // drag a rectangle.
        _ = try await runner.run(
            "/usr/sbin/screencapture",
            arguments: ["-i", "-c"],
            timeout: 600
        )

        // A cancelled selection writes nothing and still exits zero, so the
        // clipboard is the only thing that can be asked.
        guard NSPasteboard.general.changeCount != before else { return nil }
        let images = NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage]
        return images?.first
    }
}

// MARK: - Settings keys

extension SettingKey {
    public static var ocrMode: SettingKey<TextRecognizer.Mode> {
        SettingKey<TextRecognizer.Mode>("ocr.mode", default: .prose)
    }

    /// Put the recognised text straight on the clipboard.
    public static var ocrAutoCopy: SettingKey<Bool> {
        SettingKey<Bool>("ocr.autoCopy", default: true)
    }
}
