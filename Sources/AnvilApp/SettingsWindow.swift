import AnvilAI
import AnvilKit
import AnvilToolbox
import AnvilUI
import AppKit
import SwiftUI

/// The settings window.
struct SettingsWindow: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selection: SettingsSection = .general

    enum SettingsSection: Hashable {
        case general
        case permissions
        case shortcuts
        case intelligence
        case tool(ToolIdentifier)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Anvil") {
                    Label("Allgemein", systemImage: "gearshape")
                        .tag(SettingsSection.general)
                    Label("Berechtigungen", systemImage: "hand.raised")
                        .tag(SettingsSection.permissions)
                    Label("Tastenkürzel", systemImage: "command")
                        .tag(SettingsSection.shortcuts)
                    Label("Sprachmodell", systemImage: "sparkles")
                        .tag(SettingsSection.intelligence)
                }

                let toolsWithSettings = environment.registry.toolsWithSettings
                if !toolsWithSettings.isEmpty {
                    Section("Tools") {
                        ForEach(toolsWithSettings) { tool in
                            Label(tool.metadata.title, systemImage: tool.metadata.systemImage)
                                .tag(SettingsSection.tool(tool.id))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
        }
        .frame(width: AnvilSize.settingsWidth, height: AnvilSize.settingsHeight)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general:
            GeneralSettingsView()
        case .permissions:
            PermissionsSettingsView()
        case .shortcuts:
            ShortcutSettingsView()
        case .intelligence:
            IntelligenceSettingsView()
        case let .tool(id):
            if let tool = environment.registry.tool(id: id),
               let view = tool.makeSettingsView(context: environment.context) {
                view
            } else {
                EmptyStateView(
                    title: "Keine Einstellungen",
                    message: "Dieses Tool bringt keine eigenen Einstellungen mit.",
                    systemImage: "gearshape"
                )
            }
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    private var settings: SettingsStore { environment.settings }

    /// Ausschalten heißt auch aufräumen. Ein Schalter, der das Merken beendet
    /// und das bereits Gemerkte liegen lässt, sagt nicht die Wahrheit.
    private var rememberBinding: Binding<Bool> {
        settings.bind(.remembersInput) { isOn in
            if !isOn { environment.context.drafts.forgetEverything() }
        }
    }

    /// Was gerade auf der Platte liegt. Wird beim Öffnen und nach jedem
    /// Löschen neu gezählt — schätzen wäre hier das Gegenteil von Auskunft.
    @State private var stored: [StoredData] = []
    /// Was gleich gelöscht würde, sobald bestätigt ist.
    @State private var pending: StoredData.Kind?
    @State private var isClearingEverything = false

    private func rescan() {
        stored = DataInventory.scan()
    }

    private var isStorageEmpty: Bool { DataInventory.totalBytes(stored) == 0 }

    private var totalSummary: String {
        let total = DataInventory.totalBytes(stored)
        guard total > 0 else { return localized("Es liegt nichts da.") }
        let size = StoredData.size(total)
        return localized("Zusammen \(size).")
    }

    private func remove(_ kind: StoredData.Kind) {
        try? DataInventory.empty(kind)
        if kind == .history { environment.context.history.forgetEverything() }
        if kind == .drafts { environment.context.drafts.forgetEverything() }
        rescan()
    }

    private func removeEverything() {
        try? DataInventory.emptyEverything()
        environment.context.history.forgetEverything()
        environment.context.drafts.forgetEverything()
        rescan()
    }

    var body: some View {
        SettingsPage("Allgemein", description: "Verhalten der App insgesamt.") {
            SettingsGroup("Bedienung") {
                SettingsRow(
                    "Ergebnisse automatisch kopieren",
                    help: "Legt das Ergebnis nach jedem Durchlauf in die Zwischenablage. Live mitlaufende Umwandlungen sind ausgenommen.",
                    systemImage: "doc.on.doc"
                ) {
                    Toggle("", isOn: settings.bind(.autoCopyResults)).toggleStyle(.switch)
                }

                SettingsRow(
                    "Menüleisten-Symbol",
                    help: "Schnellzugriff auf Diktat und Suche, ohne das Fenster zu holen.",
                    systemImage: "menubar.arrow.up.rectangle"
                ) {
                    Toggle("", isOn: settings.bind(.showMenuBarItem)).toggleStyle(.switch)
                }
            }

            SettingsGroup(
                "Verlauf",
                footnote: "Der Verlauf liegt unverschlüsselt in ~/Library/Application Support/Anvil."
            ) {
                SettingsWideRow(
                    "Einträge pro Tool",
                    help: "Ältere Durchläufe werden verworfen, sobald die Grenze erreicht ist."
                ) {
                    Picker("", selection: settings.bind(.historyLimitPerTool)) {
                        ForEach([10, 25, 50, 100, 250], id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                SettingsRow(
                    "Datenordner",
                    help: .resolved(AppPaths.support.path(percentEncoded: false)),
                    systemImage: "folder"
                ) {
                    AnvilButton("Öffnen", role: .secondary) {
                        AppPaths.bootstrap()
                        NSWorkspace.shared.open(AppPaths.support)
                    }
                }
            }

            SettingsGroup(
                "Merken",
                footnote: "Nie gemerkt wird, was nach einem Geheimnis aussieht — Schlüssel, Tokens, Zugangsdaten — und was in Werkzeugen steht, deren Zweck Geheimnisse sind: JWT, Prüfsummen, Base64, Hex. Ergebnisse werden grundsätzlich nicht gespeichert."
            ) {
                SettingsRow(
                    "Eingaben behalten",
                    help: "Beim nächsten Öffnen steht wieder da, was zuletzt drinstand.",
                    systemImage: "arrow.counterclockwise"
                ) {
                    Toggle("", isOn: rememberBinding)
                        .toggleStyle(.switch)
                }

                SettingsRow(
                    "Gemerktes verwerfen",
                    help: "Löscht alle behaltenen Eingaben von der Platte.",
                    systemImage: "trash"
                ) {
                    AnvilButton("Verwerfen", role: .secondary) {
                        environment.context.drafts.forgetEverything()
                    }
                }
            }

            SettingsGroup(
                "Datenablage",
                footnote: "Alles davon liegt unverschlüsselt in deinem Benutzerordner und geht nie ins Netz. „Alles löschen\" lässt die eigenen Werkzeuge stehen — die sind keine Ablage, sondern Arbeit."
            ) {
                ForEach(stored) { item in
                    SettingsRow(
                        .resolved(item.kind.title),
                        help: .resolved("\(item.summary) · \(item.kind.explanation)"),
                        systemImage: item.kind.systemImage
                    ) {
                        AnvilButton("Löschen", role: .secondary) { pending = item.kind }
                            .disabled(item.isEmpty)
                    }
                }

                SettingsRow(
                    "Alles löschen",
                    help: .resolved(totalSummary),
                    systemImage: "trash"
                ) {
                    AnvilButton("Alles löschen", role: .destructive) {
                        isClearingEverything = true
                    }
                    .disabled(isStorageEmpty)
                }
            }

            SettingsGroup("Tools") {
                SettingsRow(
                    "Tool-Store",
                    help: "\(environment.registry.tools.count) von \(environment.registry.allTools.count) Tools aktiv.",
                    systemImage: "square.grid.2x2"
                ) {
                    AnvilButton("Öffnen", role: .secondary) {
                        environment.open(ToolIdentifier("system.store"))
                        NSApp.keyWindow?.close()
                    }
                }

                SettingsRow(
                    "Eigene Tools",
                    help: "JSON-Dateien in ~/Library/Application Support/Anvil/Tools.",
                    systemImage: "wrench.and.screwdriver"
                ) {
                    AnvilButton("Neu laden", role: .secondary) {
                        environment.customTools.reloadUserTools()
                    }
                }
            }
        }
        .onAppear(perform: rescan)
        .confirmationDialog(
            "Wirklich löschen?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let pending { remove(pending) }
                pending = nil
            }
            Button("Abbrechen", role: .cancel) { pending = nil }
        } message: {
            if let pending {
                Text(.resolved(pending.explanation))
            }
        }
        .confirmationDialog(
            "Alles Gespeicherte löschen?",
            isPresented: $isClearingEverything,
            titleVisibility: .visible
        ) {
            Button("Alles löschen", role: .destructive) {
                removeEverything()
                isClearingEverything = false
            }
            Button("Abbrechen", role: .cancel) { isClearingEverything = false }
        } message: {
            Text("Verlauf, gemerkte Eingaben, Aufnahmen, Bildschirmfotos und Exporte. Die eigenen Werkzeuge bleiben.")
        }
    }

}

// MARK: - Intelligence

struct IntelligenceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AIRouter.self) private var injectedRouter: AIRouter?

    @State private var apiKey = ""
    @State private var keyStatus: String?

    private var router: AIRouter { injectedRouter ?? environment.router }

    private var agent: CLIAgentProvider.Agent { environment.settings[.cliAgent] }

    private var agentHelp: LocalizedStringKey {
        environment.settings[.usesCLIAgent]
            ? .resolved(agent.explanation)
            : "Erst oben einschalten."
    }

    /// Anything on this page changes what the router will do next, so every
    /// write is followed by a fresh look at whether the model is reachable.
    private func binding<Value>(_ key: SettingKey<Value>) -> Binding<Value> {
        environment.settings.bind(key) { _ in
            Task { await router.refreshAvailability() }
        }
    }

    var body: some View {
        SettingsPage(
            "Sprachmodell",
            description: "Welches Modell antwortet — und ob dafür etwas diesen Mac verlässt."
        ) {
            SettingsGroup("Status") {
                SettingsRow(
                    router.availability.isAvailable ? "Bereit" : "Nicht verfügbar",
                    help: .resolved(router.statusSummary),
                    systemImage: router.activeRunsOnDevice ? "laptopcomputer" : "cloud"
                ) {
                    AnvilButton("Prüfen", systemImage: "arrow.clockwise", role: .secondary, isBusy: router.isRefreshing) {
                        Task { await router.refreshAvailability() }
                    }
                }
            }

            SettingsGroup("Richtlinie", footnote: .resolved(router.policy.explanation)) {
                SettingsWideRow("Wohin gehen Anfragen?") {
                    Picker("", selection: policyBinding) {
                        ForEach(AIPolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            SettingsGroup(
                "Installiertes Werkzeug",
                footnote: "Nutzt die Anmeldung, die auf diesem Mac schon eingerichtet ist — kein Schlüssel, kein Konto mehr. Antworten kommen am Stück, nicht Wort für Wort."
            ) {
                SettingsRow(
                    "Über ein Kommandozeilen-Werkzeug",
                    help: .resolved(agent.explanation),
                    systemImage: "terminal"
                ) {
                    Toggle("", isOn: binding(.usesCLIAgent))
                        .toggleStyle(.switch)
                }

                SettingsWideRow("Werkzeug", help: agentHelp) {
                    Picker("", selection: binding(.cliAgent)) {
                        ForEach(CLIAgentProvider.Agent.allCases) { agent in
                            Text(agent.title).tag(agent)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!environment.settings[.usesCLIAgent])
                }

                if agent == .custom || !environment.settings[.cliAgentExecutable].isEmpty {
                    SettingsWideRow(
                        "Befehl",
                        help: "Voller Pfad oder Name im Pfad. Der Prompt wird als letztes Argument angehängt."
                    ) {
                        AnvilTextField(
                            text: binding(.cliAgentExecutable),
                            placeholder: "claude",
                            isMonospaced: true
                        )
                    }

                    SettingsWideRow(
                        "Argumente",
                        help: "Stehen vor dem Prompt. Leer lassen für die Vorgabe des Werkzeugs."
                    ) {
                        AnvilTextField(
                            text: binding(.cliAgentArguments),
                            placeholder: "-p",
                            isMonospaced: true
                        )
                    }
                }

                SettingsRow(
                    "Erneut suchen",
                    help: "Vergisst den gemerkten Pfad — nötig, wenn du das Werkzeug gerade erst installiert hast.",
                    systemImage: "magnifyingglass"
                ) {
                    AnvilButton("Suchen", role: .secondary) {
                        Task {
                            await CLIAgentLocator.shared.forget()
                            await router.refreshAvailability()
                        }
                    }
                }
            }

            SettingsGroup(
                "Externer Anbieter",
                footnote: "Wird nur benutzt, wenn die Richtlinie es zulässt und oben kein Werkzeug eingeschaltet ist. Der Schlüssel liegt im Schlüsselbund, nicht in den Einstellungen."
            ) {
                SettingsWideRow("Voreinstellung") {
                    Picker("", selection: presetBinding) {
                        ForEach(RemoteConfiguration.presets, id: \.presetID) { preset in
                            Text(.resolved(localized(runtime: preset.presetName)))
                                .tag(preset.presetID)
                        }
                    }
                }

                SettingsWideRow("Adresse", help: "Basis-URL der API, z. B. http://localhost:11434/v1") {
                    AnvilTextField(text: baseURLBinding, placeholder: "https://…", isMonospaced: true)
                }

                SettingsWideRow("Modell", help: "Genauer Modellname beim Anbieter.") {
                    AnvilTextField(text: modelBinding, placeholder: "z. B. llama3.2", isMonospaced: true)
                }

                if router.remoteConfiguration.requiresAPIKey {
                    SettingsWideRow("API-Schlüssel", help: .resolvedIfPresent(keyStatus)) {
                        HStack(spacing: AnvilSpacing.sm) {
                            AnvilTextField(text: $apiKey, placeholder: "sk-…", isSecure: true)
                            AnvilButton("Sichern", role: .secondary) { saveKey() }
                            AnvilButton("Löschen", role: .destructive) { saveKey(clearing: true) }
                        }
                    }
                }
            }

            GitHubSettingsView(
                settings: environment.settings,
                pasteboard: environment.context.pasteboard
            )
        }
        .task { loadKeyStatus() }
    }

    // MARK: Bindings

    private var policyBinding: Binding<AIPolicy> {
        Binding(get: { router.policy }, set: { router.policy = $0 })
    }

    private var presetBinding: Binding<String> {
        Binding(
            get: { router.remoteConfiguration.presetID },
            set: { id in
                guard let preset = RemoteConfiguration.presets.first(where: { $0.presetID == id }) else { return }
                var configuration = preset
                if preset.model.isEmpty { configuration.model = router.remoteConfiguration.model }
                router.remoteConfiguration = configuration
                loadKeyStatus()
            }
        )
    }

    private var baseURLBinding: Binding<String> {
        Binding(
            get: { router.remoteConfiguration.baseURL },
            set: { router.remoteConfiguration.baseURL = $0 }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { router.remoteConfiguration.model },
            set: { router.remoteConfiguration.model = $0 }
        )
    }

    // MARK: Keychain

    private func loadKeyStatus() {
        apiKey = ""
        keyStatus = router.apiKey().map { _ in "Ein Schlüssel ist hinterlegt." }
            ?? "Noch kein Schlüssel hinterlegt."
    }

    private func saveKey(clearing: Bool = false) {
        do {
            try router.setAPIKey(clearing ? nil : apiKey)
            apiKey = ""
            keyStatus = clearing ? "Schlüssel gelöscht." : "Schlüssel gesichert."
        } catch {
            keyStatus = AnvilError.wrapping(error).message
        }
    }
}
