import AnvilAI
import AnvilKit
import AnvilUI
import AppKit
import SwiftUI

/// The settings window.
///
/// A sidebar rather than the usual toolbar tabs, because the number of pages
/// grows with the number of installed tools — every tool that registers a
/// settings view shows up here automatically.
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
        .frame(width: 860, height: 600)
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

    var body: some View {
        SettingsPage("Allgemein", description: "Verhalten der App insgesamt.") {
            SettingsGroup("Bedienung") {
                SettingsRow(
                    "Ergebnisse automatisch kopieren",
                    help: "Legt das Ergebnis nach jedem Durchlauf in die Zwischenablage. Live mitlaufende Umwandlungen sind ausgenommen.",
                    systemImage: "doc.on.doc"
                ) {
                    Toggle("", isOn: binding(.autoCopyResults)).toggleStyle(.switch)
                }

                SettingsRow(
                    "Menüleisten-Symbol",
                    help: "Schnellzugriff auf Diktat und Suche, ohne das Fenster zu holen.",
                    systemImage: "menubar.arrow.up.rectangle"
                ) {
                    Toggle("", isOn: binding(.showMenuBarItem)).toggleStyle(.switch)
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
                    Picker("", selection: binding(.historyLimitPerTool)) {
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
    }

    private func binding<Value>(_ key: SettingKey<Value>) -> Binding<Value> {
        Binding(get: { settings[key] }, set: { settings[key] = $0 })
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

    private func binding<Value>(_ key: SettingKey<Value>) -> Binding<Value> {
        Binding(
            get: { environment.settings[key] },
            set: { newValue in
                environment.settings[key] = newValue
                Task { await router.refreshAvailability() }
            }
        )
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
                            Text(preset.presetName).tag(preset.presetID)
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
                // Carry the model name over when switching between endpoints
                // that are likely to serve the same model.
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
