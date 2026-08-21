import AnvilKit
import Foundation
import Testing

@testable import AnvilAI

@Suite("Der Agent auf der Kommandozeile")
struct CLIAgentTests {
    private func provider(
        _ agent: CLIAgentProvider.Agent,
        executable: String = "",
        arguments: [String] = []
    ) -> CLIAgentProvider {
        CLIAgentProvider(agent: agent, customExecutable: executable, customArguments: arguments)
    }

    private let request = AIRequest(instructions: "Sei knapp.", prompt: "Hallo")

    // MARK: - Die Anweisung

    /// Claude Code nimmt die Anweisung als Systemprompt. Vorne im Text stehend
    /// wäre sie nur der Anfang der Eingabe.
    @Test
    func claudeCodeGetsTheInstructionsAsASystemPrompt() {
        let call = provider(.claudeCode).call(for: request)
        #expect(call.contains("--append-system-prompt"))
        #expect(call.contains("Sei knapp."))
        #expect(call.last == "Hallo")
    }

    /// Die anderen kennen dafür kein Argument — dort bleibt nur, sie vor den
    /// Prompt zu setzen.
    @Test
    func theOthersGetThemInFrontOfThePrompt() {
        for agent in [CLIAgentProvider.Agent.codex, .gemini] {
            let call = provider(agent).call(for: request)
            #expect(!call.contains("--append-system-prompt"))
            #expect(call.last == "Sei knapp.\n\nHallo")
        }
    }

    @Test
    func withoutInstructionsOnlyThePromptIsPassed() {
        let call = provider(.claudeCode).call(for: AIRequest(instructions: "", prompt: "Hallo"))
        #expect(call == ["-p", "Hallo"])
    }

    // MARK: - Eigene Argumente

    /// Sie kommen dazu, statt zu ersetzen: Ohne `-p` antwortet Claude Code
    /// nicht, und wer `--model` einträgt, will das `-p` nicht verlieren.
    @Test
    func ownArgumentsAreAddedToTheDefaults() {
        let call = provider(.claudeCode, arguments: ["--model", "opus"]).call(for: request)
        #expect(call.starts(with: ["-p", "--model", "opus"]))
    }

    /// Beim eigenen Befehl gibt es keine Vorgabe, die dazukommen könnte.
    @Test
    func theOwnCommandKeepsOnlyWhatWasTyped() {
        let call = provider(.custom, executable: "/usr/bin/true", arguments: ["--los"])
            .call(for: AIRequest(instructions: "", prompt: "Hallo"))
        #expect(call == ["--los", "Hallo"])
    }

    // MARK: - Kennungen

    @Test
    func everyAgentKnowsHowItIsCalled() {
        for agent in CLIAgentProvider.Agent.allCases where agent != .custom {
            #expect(!agent.executable.isEmpty, "\(agent.title) hat keinen Befehl")
            #expect(!agent.arguments.isEmpty, "\(agent.title) hat keine Argumente")
        }
        #expect(CLIAgentProvider.Agent.claudeCode.executable == "claude")
    }

    /// Ein Agent läuft hier, redet aber mit einem Dienst. Die Anzeige darf
    /// nichts anderes behaupten.
    @Test
    func anAgentIsNotOnDevice() {
        #expect(!provider(.claudeCode).runsOnDevice)
    }
}
