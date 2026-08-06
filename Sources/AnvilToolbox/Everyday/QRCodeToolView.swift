import AnvilKit
import AnvilUI
import AppKit
import Foundation
import SwiftUI

/// Text in, QR code out — and the other way round.
public struct QRCodeToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var text = ""
    @State private var error: AnvilError?
    @State private var exportedURL: URL?

    public init(context: ToolContext, metadata: ToolMetadata) {
        self.context = context
        self.metadata = metadata
    }

    private var settings: SettingsStore { context.settings }

    public var body: some View {
        ToolScaffold(metadata: metadata) {
            content
        } inspector: {
            inspector
        } actions: {
            AnvilButton("Aus der Zwischenablage lesen", systemImage: "qrcode.viewfinder") {
                readFromPasteboard()
            }
        }
        .anvilErrorBanner($error)
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(storageKey: metadata.id.rawValue) {
            AnvilPane("Inhalt", systemImage: "text.alignleft") {
                AnvilTextEditor(
                    text: $text,
                    placeholder: "Adresse, WLAN-Zugang, Telefonnummer, beliebiger Text …"
                )
            } accessory: {
                Button { text = context.pasteboard.string() ?? text } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Einfügen")
            }
        } secondary: {
            codePane
        } status: {
            statusBar
        }
    }

    private var codePane: some View {
        AnvilPane("Code", systemImage: "qrcode") {
            switch rendered {
            case .empty:
                EmptyStateView(
                    title: "Noch kein Code",
                    message: "Schreib links etwas hinein — der Code entsteht sofort.",
                    systemImage: "qrcode"
                )
            case .failure(let message):
                EmptyStateView(
                    title: "Passt nicht in einen Code",
                    message: .resolved(message),
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            case .success(let image):
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(AnvilSpacing.lg)
            }
        } accessory: {
            if case .success = rendered {
                Button(action: copyImage) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Bild kopieren")

                Button(action: exportImage) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Als PNG sichern")
            }
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(text.count)", label: "Zeichen", systemImage: "character")
            StatusMetric("\(Data(text.utf8).count)", label: "Bytes", systemImage: "number")
        } trailing: {
            if let exportedURL {
                Button { NSWorkspace.shared.activateFileViewerSelecting([exportedURL]) } label: {
                    StatusPill("Gesichert", systemImage: "checkmark", tone: .success)
                }
                .buttonStyle(.plain)
            }
            StatusPill(.resolved(correction.title), systemImage: "shield", tone: .neutral)
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Fehlerkorrektur",
            systemImage: "shield",
            footnote: .resolved(correction.explanation)
        ) {
            ChipPicker(
                selection: correctionBinding,
                options: QRCode.Correction.allCases,
                title: \.title
            )
        }

        InspectorSection(
            "Vorlagen",
            systemImage: "square.grid.2x2",
            footnote: "Setzt den Inhalt auf ein Format, das Telefone erkennen."
        ) {
            AnvilButton("WLAN-Zugang", systemImage: "wifi") {
                text = "WIFI:T:WPA;S:Netzname;P:Passwort;;"
            }
            AnvilButton("Visitenkarte", systemImage: "person.crop.square") {
                text = """
                BEGIN:VCARD
                VERSION:3.0
                N:Nachname;Vorname
                TEL:+49
                EMAIL:
                END:VCARD
                """
            }
            AnvilButton("Termin", systemImage: "calendar") {
                text = """
                BEGIN:VEVENT
                SUMMARY:Titel
                DTSTART:20260101T090000
                DTEND:20260101T100000
                END:VEVENT
                """
            }
        }
    }

    // MARK: - Rendering

    private enum Rendered {
        case empty
        case success(NSImage)
        case failure(String)
    }

    private var rendered: Rendered {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        do {
            return .success(try QRCode.image(for: text, correction: correction))
        } catch {
            return .failure(AnvilError.wrapping(error).message)
        }
    }

    private var correction: QRCode.Correction {
        settings[.qrCorrection]
    }

    private var correctionBinding: Binding<QRCode.Correction> {
        Binding(
            get: { settings[.qrCorrection] },
            set: { settings[.qrCorrection] = $0 }
        )
    }

    // MARK: - Actions

    private func copyImage() {
        guard case .success(let image) = rendered else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func exportImage() {
        guard case .success(let image) = rendered else { return }
        do {
            let stamp = ISO8601DateFormatter().string(from: .now)
                .replacingOccurrences(of: ":", with: "-")
            exportedURL = try QRCode.export(image, named: "QR \(stamp)")
        } catch {
            self.error = AnvilError.wrapping(error)
        }
    }

    /// Reads a QR code out of an image sitting on the clipboard — a screenshot,
    /// usually, which is how a code on screen gets here.
    private func readFromPasteboard() {
        let objects = NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage]
        guard let image = objects?.first else {
            error = .invalidInput(localized("In der Zwischenablage liegt kein Bild."))
            return
        }

        let found = QRCode.read(image)
        guard let first = found.first else {
            error = .invalidInput(localized("In dem Bild ist kein QR-Code zu finden."))
            return
        }
        text = found.count > 1 ? found.joined(separator: "\n") : first
    }
}
