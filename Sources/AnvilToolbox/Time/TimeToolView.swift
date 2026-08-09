import AnvilKit
import AnvilUI
import SwiftUI

/// Zeit ausrechnen: Dauern, Zeitstempel, Abstände, Zeitzonen.
///
/// Vier Fragen, die im Alltag ständig auftauchen und für die man sonst jedes
/// Mal eine Webseite aufmacht — mit dem Unterschied, dass hier nichts von dem,
/// was man eintippt, das Gerät verlässt.
public struct TimeToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    private enum Mode: String, Hashable, CaseIterable, Identifiable {
        case duration
        case timestamp
        case span

        var id: String { rawValue }

        var title: String {
            switch self {
            case .duration: localized("Dauer")
            case .timestamp: localized("Zeitstempel")
            case .span: localized("Abstand")
            }
        }

        var systemImage: String {
            switch self {
            case .duration: "hourglass"
            case .timestamp: "number"
            case .span: "calendar"
            }
        }
    }

    @State private var mode: Mode = .duration
    @State private var durationInput = ""
    @State private var timestampInput = ""
    @State private var startInput = ""
    @State private var endInput = ""
    @State private var durationStyle: TimeMath.DurationStyle = .compact
    @State private var dropError: AnvilError?

    /// Der Bezugspunkt für „jetzt".
    ///
    /// Einmal beim Öffnen genommen und danach nur noch auf Knopfdruck neu:
    /// eine Zeile, die sich beim Zusehen ändert, kann man nicht abschreiben.
    @State private var now = Date()

    public init(context: ToolContext, metadata: ToolMetadata) {
        self.context = context
        self.metadata = metadata
    }

    public var body: some View {
        ToolScaffold(metadata: metadata) {
            content
        } inspector: {
            inspector
        } actions: {
            AnvilButton("Jetzt", systemImage: "clock.arrow.circlepath") { now = Date() }
        }
        .anvilErrorBanner($dropError)
        .onAppear(perform: restore)
        .onDisappear(perform: remember)
    }

    private func restore() {
        now = Date()
        guard let draft = context.drafts.draft(for: metadata.id) else { return }
        durationInput = draft.input
        timestampInput = draft.extra("timestamp")
        startInput = draft.extra("start")
        endInput = draft.extra("end")
    }

    private func remember() {
        context.drafts.save(
            DraftStore.Draft(
                input: durationInput,
                extras: ["timestamp": timestampInput, "start": startInput, "end": endInput]
            ),
            for: metadata.id,
            allowed: context.settings[.remembersInput]
        )
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: AnvilSpacing.md) {
            ChipPicker(
                selection: $mode,
                options: Mode.allCases,
                title: { $0.title },
                systemImage: { $0.systemImage }
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            switch mode {
            case .duration: durationPane
            case .timestamp: timestampPane
            case .span: spanPane
            }
        }
        .padding(AnvilSpacing.md)
    }

    // MARK: Dauer

    private var duration: TimeInterval? { TimeMath.seconds(parsing: durationInput) }

    private var durationPane: some View {
        AnvilPane("Dauer", systemImage: "hourglass", contentInset: true) {
            VStack(alignment: .leading, spacing: AnvilSpacing.md) {
                AnvilTextField(
                    text: $durationInput,
                    placeholder: "90m, 1h 30m, 2 Tage, 1:30:00",
                    isMonospaced: true
                )

                if let duration {
                    KeyValueList(TimeMath.DurationStyle.allCases.map { style in
                        KeyValueList.Item(
                            style.title,
                            TimeMath.text(duration, style: style),
                            tone: style == durationStyle ? .accent : .neutral
                        )
                    })

                    KeyValueList([
                        KeyValueList.Item(localized("In Sekunden"), Self.plain(duration)),
                        KeyValueList.Item(localized("In Minuten"), Self.plain(duration / 60)),
                        KeyValueList.Item(localized("In Stunden"), Self.plain(duration / 3600)),
                        KeyValueList.Item(localized("In Tagen"), Self.plain(duration / 86400))
                    ])

                    KeyValueList([
                        KeyValueList.Item(
                            localized("Ab jetzt"),
                            Self.moment(now.addingTimeInterval(duration))
                        ),
                        KeyValueList.Item(
                            localized("Vor jetzt"),
                            Self.moment(now.addingTimeInterval(-duration))
                        )
                    ])
                } else if durationInput.isEmpty {
                    EmptyStateView(
                        title: "Noch keine Dauer",
                        message: "90m, 1h 30m, 2 Tage, 1:30:00 — alles davon geht.",
                        systemImage: "hourglass"
                    )
                } else {
                    AnvilBanner(
                        title: "Das ist keine Dauer",
                        message: "Erlaubt sind Zahlen mit einer Einheit — s, m, h, d, w — oder die Uhrzeit-Schreibweise.",
                        tone: .warning
                    )
                }

                Spacer(minLength: 0)
            }
        } accessory: {
            CopyButton(text: duration.map { TimeMath.text($0, style: durationStyle) } ?? "")
        }
    }

    // MARK: Zeitstempel

    private var timestamp: (date: Date, unit: TimeMath.TimestampUnit)? {
        TimeMath.timestamp(parsing: timestampInput)
            ?? TimeMath.date(parsing: timestampInput, in: .current).map { ($0, .seconds) }
    }

    private var timestampPane: some View {
        AnvilPane("Zeitstempel", systemImage: "number", contentInset: true) {
            VStack(alignment: .leading, spacing: AnvilSpacing.md) {
                AnvilTextField(
                    text: $timestampInput,
                    placeholder: "1786310000 oder 2026-08-09T21:00:00Z",
                    isMonospaced: true
                )

                if let timestamp {
                    let week = TimeMath.isoWeek(of: timestamp.date)
                    KeyValueList([
                        KeyValueList.Item(localized("Erkannt als"), timestamp.unit.title, tone: .accent),
                        KeyValueList.Item(localized("Örtlich"), Self.moment(timestamp.date)),
                        KeyValueList.Item(
                            localized("ISO 8601"),
                            TimeMath.isoText(of: timestamp.date, in: .current)
                        ),
                        KeyValueList.Item(localized("UTC"), TimeMath.isoText(of: timestamp.date, in: .gmt)),
                        KeyValueList.Item(localized("Kalenderwoche"), "\(week.week)/\(week.year)")
                    ])

                    KeyValueList(TimeMath.TimestampUnit.allCases.map { unit in
                        KeyValueList.Item(
                            unit.title,
                            TimeMath.timestampText(of: timestamp.date, unit: unit)
                        )
                    })

                    zoneTable(for: timestamp.date)
                } else if timestampInput.isEmpty {
                    EmptyStateView(
                        title: "Noch kein Zeitpunkt",
                        message: "Ein Unix-Zeitstempel, ein ISO-Datum oder 09.08.2026 — die Einheit erkennt Anvil selbst.",
                        systemImage: "number",
                        actions: {
                            AnvilButton("Jetzt einsetzen", systemImage: "clock") {
                                timestampInput = TimeMath.timestampText(of: now, unit: .seconds)
                            }
                        }
                    )
                } else {
                    AnvilBanner(
                        title: "Das ist kein Zeitpunkt",
                        message: "Erwartet wird ein Unix-Zeitstempel oder ein Datum.",
                        tone: .warning
                    )
                }

                Spacer(minLength: 0)
            }
        } accessory: {
            CopyButton(text: timestamp.map { TimeMath.isoText(of: $0.date, in: .current) } ?? "")
        }
    }

    /// Derselbe Augenblick an mehreren Orten.
    private func zoneTable(for date: Date) -> some View {
        AnvilSection("Anderswo", subtitle: "Derselbe Augenblick, andere Uhr") {
            KeyValueList(Self.zones.map { identifier in
                let zone = TimeZone(identifier: identifier) ?? .gmt
                return KeyValueList.Item(identifier, Self.moment(date, in: zone))
            })
        }
    }

    /// Eine kleine, feste Auswahl. Wer eine andere braucht, tippt sie in die
    /// Suche der Systemuhr — ein Werkzeug mit 400 Einträgen hilft niemandem.
    private static let zones = [
        "UTC",
        "Europe/Berlin",
        "Europe/London",
        "America/New_York",
        "America/Los_Angeles",
        "Asia/Kolkata",
        "Asia/Tokyo",
        "Australia/Sydney"
    ]

    // MARK: Abstand

    private var spanDates: (start: Date, end: Date)? {
        guard let start = TimeMath.date(parsing: startInput, in: .current),
              let end = TimeMath.date(parsing: endInput, in: .current)
        else { return nil }
        return (start, end)
    }

    private var spanPane: some View {
        AnvilPane("Abstand", systemImage: "calendar", contentInset: true) {
            VStack(alignment: .leading, spacing: AnvilSpacing.md) {
                HStack(spacing: AnvilSpacing.sm) {
                    AnvilTextField(text: $startInput, placeholder: "Von — 2026-08-09", isMonospaced: true)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AnvilColor.textTertiary)
                    AnvilTextField(text: $endInput, placeholder: "Bis — 2026-12-24", isMonospaced: true)
                }

                HStack(spacing: AnvilSpacing.sm) {
                    AnvilButton("Heute als Von", systemImage: "arrow.left.to.line") {
                        startInput = Self.day(now)
                    }
                    AnvilButton("Heute als Bis", systemImage: "arrow.right.to.line") {
                        endInput = Self.day(now)
                    }
                }

                if let dates = spanDates {
                    let span = TimeMath.span(from: dates.start, to: dates.end)
                    KeyValueList([
                        KeyValueList.Item(localized("Tage"), "\(span.days)", tone: .accent),
                        KeyValueList.Item(localized("Arbeitstage"), "\(span.workdays)", tone: .accent),
                        KeyValueList.Item(localized("Wochen"), "\(span.weeks)"),
                        KeyValueList.Item(localized("Monate"), "\(span.months)"),
                        KeyValueList.Item(localized("Jahre"), "\(span.years)"),
                        KeyValueList.Item(
                            localized("Dauer"),
                            TimeMath.text(span.seconds, style: durationStyle)
                        )
                    ])
                } else {
                    EmptyStateView(
                        title: "Zwei Zeitpunkte",
                        message: "Beide Felder füllen — 2026-08-09, 09.08.2026 oder ein Zeitstempel.",
                        systemImage: "calendar"
                    )
                }

                Spacer(minLength: 0)
            }
        } accessory: {
            CopyButton(text: spanDates.map { "\(TimeMath.span(from: $0.start, to: $0.end).days)" } ?? "")
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Schreibweise",
            systemImage: "textformat",
            footnote: "Gilt für den Kopieren-Knopf und für die Dauer beim Abstand."
        ) {
            ChipPicker(
                selection: $durationStyle,
                options: TimeMath.DurationStyle.allCases,
                title: { $0.title }
            )
        }

        InspectorSection("Jetzt", systemImage: "clock") {
            KeyValueList([
                KeyValueList.Item(localized("Örtlich"), Self.moment(now)),
                KeyValueList.Item(localized("Zeitstempel"), TimeMath.timestampText(of: now, unit: .seconds)),
                KeyValueList.Item(
                    localized("Kalenderwoche"),
                    "\(TimeMath.isoWeek(of: now).week)/\(TimeMath.isoWeek(of: now).year)"
                ),
                KeyValueList.Item(localized("Zeitzone"), TimeZone.current.identifier)
            ])
        }

        InspectorSection("Einheiten", systemImage: "ruler") {
            KeyValueList([
                KeyValueList.Item(localized("Sekunden"), "s, sek"),
                KeyValueList.Item(localized("Minuten"), "m, min"),
                KeyValueList.Item(localized("Stunden"), "h, std"),
                KeyValueList.Item(localized("Tage"), "d, t, tag"),
                KeyValueList.Item(localized("Wochen"), "w, woche")
            ])
        }
    }

    // MARK: - Kleinkram

    /// Eine Zahl ohne unnötige Nachkommastellen.
    private static func plain(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15
            ? String(Int64(value))
            : String(format: "%.3f", value).replacingOccurrences(of: ".", with: ",")
    }

    private static func moment(_ date: Date, in zone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
