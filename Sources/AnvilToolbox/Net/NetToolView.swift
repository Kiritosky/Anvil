import AnvilKit
import AnvilUI
import SwiftUI

/// Netze rechnen — eins oder zweihundert.
///
/// Die Eingabe ist bewusst ein Textfeld und kein Formular mit vier Oktett-
/// Feldern: Netze kommen aus einer Konfiguration, aus einem Ticket oder aus
/// einer Tabelle, und dort stehen sie als Text, oft gleich mehrere. Wer sie
/// erst in Einzelfelder abtippt, hat den Nutzen des Werkzeugs schon verloren.
public struct NetToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var input = ""
    @State private var probe = ""
    @State private var isSplitting = false
    @State private var splitPrefix = 26
    @State private var dropError: AnvilError?
    @State private var orientation: WorkbenchOrientation = .horizontal

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
            AnvilButton("Normalform", systemImage: "wand.and.rays") {
                input = list.normalizedText
            }
            .disabled(list.networks.isEmpty)

            WorkbenchOrientationPicker(orientation: $orientation)
        }
        .anvilErrorBanner($dropError)
        .anvilFileDrop(.text, error: $dropError) { dropped in
            guard case let .text(text, _) = dropped else { return }
            input = text
        }
        .onAppear(perform: restore)
        .onDisappear(perform: remember)
    }

    // MARK: - Zurückholen und merken

    private func restore() {
        guard let draft = context.drafts.draft(for: metadata.id) else { return }
        input = draft.input
        probe = draft.extra("probe")
    }

    private func remember() {
        context.drafts.save(
            DraftStore.Draft(input: input, extras: ["probe": probe]),
            for: metadata.id,
            allowed: context.settings[.remembersInput]
        )
    }

    // MARK: - Content

    private var list: NetworkList { NetworkList(parsing: input) }

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
            inputPane
        } secondary: {
            resultPane
        } status: {
            statusBar
        }
    }

    private var inputPane: some View {
        AnvilPane("Netze", systemImage: "network") {
            AnvilTextEditor(
                text: $input,
                placeholder: "192.168.1.0/24\n10.0.0.0 255.255.0.0\n2001:db8::/48",
                isMonospaced: true
            )
        } accessory: {
            Button { input = context.pasteboard.string() ?? input } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp("Einfügen")
        }
    }

    private var resultPane: some View {
        AnvilPane(
            list.single == nil ? "Übersicht" : "Steckbrief",
            systemImage: list.single == nil ? "list.bullet.rectangle" : "info.circle",
            tone: .neutral
        ) {
            if list.isEmpty {
                EmptyStateView(
                    title: "Noch kein Netz",
                    message: "Ein Netz je Zeile — mit Präfixlänge, mit Maske oder als nackte Adresse.",
                    systemImage: "network"
                )
            } else if let single = list.single {
                detail(of: single)
            } else {
                overview
            }
        } accessory: {
            CopyButton(text: list.single.map(reportText) ?? list.report)
        }
    }

    // MARK: Ein Netz

    private func detail(of network: IPNetwork) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: AnvilSpacing.md) {
                HStack(spacing: AnvilSpacing.sm) {
                    StatusPill(.resolved(network.family.title), tone: .accent)
                    StatusPill(
                        .resolved(network.scope.title),
                        systemImage: network.scope.systemImage,
                        tone: network.scope.tone.uiTone
                    )
                    Spacer(minLength: 0)
                }

                if let note = network.note {
                    AnvilBanner(title: .resolved(note), tone: .info)
                }

                KeyValueList(network.details.map { KeyValueList.Item($0.key, $0.value) })

                if !probe.isEmpty {
                    containmentRow(network.containment(of: probe))
                }

                if isSplitting {
                    splitSection(of: network)
                }
            }
            .padding(AnvilSpacing.md)
        }
    }

    private func containmentRow(_ containment: IPNetwork.Containment) -> some View {
        HStack(spacing: AnvilSpacing.sm) {
            StatusPill(
                .resolved(containment.title),
                systemImage: containment.systemImage,
                tone: containment.tone.uiTone
            )
            Text(verbatim: probe)
                .font(AnvilFont.mono)
                .foregroundStyle(AnvilColor.textSecondary)
            Spacer(minLength: 0)
        }
    }

    /// Ein Teilnetz kann kleiner sein, als das Netz erlaubt — dann steht am
    /// Regler eine Zahl, die nicht geht, und das Ergebnis ist der Grund dafür
    /// und keine leere Liste.
    private func subnets(of network: IPNetwork) -> Result<IPNetwork.Split, AnvilError> {
        do {
            return .success(try network.split(into: splitPrefix))
        } catch {
            return .failure(AnvilError.wrapping(error))
        }
    }

    @ViewBuilder
    private func splitSection(of network: IPNetwork) -> some View {
        switch subnets(of: network) {
        case let .failure(error):
            AnvilBanner(error: error)
        case let .success(split):
            VStack(alignment: .leading, spacing: AnvilSpacing.sm) {
                HStack(spacing: AnvilSpacing.sm) {
                    Text("Teilnetze")
                        .textCase(.uppercase)
                        .font(AnvilFont.label)
                        .foregroundStyle(AnvilColor.textTertiary)
                    StatusPill(.resolved(IPMath.grouped(split.countText)), tone: .accent)
                    if split.isTruncated {
                        StatusPill("gekürzt", systemImage: "scissors", tone: .warning)
                    }
                    Spacer(minLength: 0)
                    CopyButton(text: split.subnets.map(\.description).joined(separator: "\n"))
                }

                ForEach(split.subnets, id: \.self) { subnet in
                    HStack(spacing: AnvilSpacing.sm) {
                        Text(verbatim: subnet.description)
                            .font(AnvilFont.mono)
                            .foregroundStyle(AnvilColor.textPrimary)
                        Spacer(minLength: 0)
                        Text(verbatim: subnet.rangeText)
                            .font(AnvilFont.monoSmall)
                            .foregroundStyle(AnvilColor.textTertiary)
                    }
                    .padding(.horizontal, AnvilSpacing.sm)
                    .padding(.vertical, AnvilSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                            .fill(AnvilColor.surface)
                    }
                }
            }
        }
    }

    // MARK: Viele Netze

    private var overview: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: AnvilSpacing.xs) {
                ForEach(list.entries) { entry in
                    row(for: entry)
                }
            }
            .padding(AnvilSpacing.md)
        }
    }

    @ViewBuilder
    private func row(for entry: NetworkList.Entry) -> some View {
        let containment = probe.isEmpty ? nil : entry.network?.containment(of: probe)

        VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
            HStack(spacing: AnvilSpacing.sm) {
                Text(verbatim: entry.network?.description ?? entry.text)
                    .font(AnvilFont.mono)
                    .foregroundStyle(entry.isReadable ? AnvilColor.textPrimary : AnvilColor.warning)
                    .textSelection(.enabled)

                if let containment, containment == .inside {
                    StatusPill(
                        .resolved(containment.title),
                        systemImage: containment.systemImage,
                        tone: .success
                    )
                }

                Spacer(minLength: 0)

                if let network = entry.network {
                    StatusPill(
                        .resolved(network.scope.title),
                        systemImage: network.scope.systemImage,
                        tone: network.scope.tone.uiTone
                    )
                }
            }

            if let network = entry.network {
                HStack(spacing: AnvilSpacing.sm) {
                    Text(verbatim: network.rangeText)
                    Text(verbatim: IPMath.grouped(network.addressCountText))
                }
                .font(AnvilFont.monoSmall)
                .foregroundStyle(AnvilColor.textTertiary)
            } else if let message = entry.message {
                Text(verbatim: message)
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
            }
        }
        .padding(AnvilSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                .fill(containment == .inside ? AnvilTone.success.fill : AnvilColor.surface)
        }
    }

    // MARK: Statuszeile

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(list.readableCount)", label: "Netze", systemImage: "network")
            if list.unreadableCount > 0 {
                StatusMetric(
                    "\(list.unreadableCount)",
                    label: "nicht lesbar",
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            }
            if !probe.isEmpty {
                StatusMetric(
                    "\(list.entries(containing: probe).count)",
                    label: "Treffer",
                    systemImage: "scope",
                    tone: .success
                )
            }
        } trailing: {
            if let single = list.single {
                StatusPill(.resolved(single.family.title), tone: .neutral)
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Adresse suchen",
            systemImage: "scope",
            footnote: "Zeigt, in welche der Netze oben diese Adresse fällt."
        ) {
            AnvilTextField(text: $probe, placeholder: "192.168.1.42", isMonospaced: true)
        }

        InspectorSection(
            "Teilen",
            systemImage: "square.split.2x2",
            footnote: "Zerlegt das Netz in gleich große Teile. Gezeigt werden die ersten 64."
        ) {
            Toggle("Teilnetze zeigen", isOn: $isSplitting)
                .font(AnvilFont.body)

            OptionRow("Neue Präfixlänge") {
                AnvilStepper(value: $splitPrefix, in: 0...maximumPrefixLength) { "/\($0)" }
            }
            .disabled(!isSplitting)
        }

        InspectorSection(
            "Übliche IPv4-Größen",
            systemImage: "ruler",
            footnote: "Benutzbare Hosts je Netz, ohne Netz- und Broadcast-Adresse."
        ) {
            KeyValueList(
                [30, 29, 28, 27, 26, 24, 22, 16].map { prefix in
                    KeyValueList.Item("/\(prefix)", hostSummary(prefix))
                }
            )
        }
    }

    /// Die Grenze richtet sich nach dem Netz, das gerade dasteht — ein /64 aus
    /// einem IPv4-Netz zu schneiden ist keine Eingabe, die man erst zulassen
    /// und dann ablehnen muss.
    private var maximumPrefixLength: Int {
        list.single?.family.maximumPrefixLength
            ?? list.networks.first?.family.maximumPrefixLength
            ?? 32
    }

    private func hostSummary(_ prefix: Int) -> String {
        IPMath.grouped("\((UInt64(1) << (32 - prefix)) - 2)")
    }

    /// Der Steckbrief als Text — dasselbe, was auf dem Schirm steht.
    private func reportText(_ network: IPNetwork) -> String {
        network.details.map { "\($0.key)\t\($0.value)" }.joined(separator: "\n")
    }
}

extension AnvilScopeTone {
    /// Die Einordnung kennt das Design-System nicht — hier wird übersetzt.
    var uiTone: AnvilTone {
        switch self {
        case .neutral: .neutral
        case .accent: .accent
        case .info: .info
        case .warning: .warning
        }
    }
}
