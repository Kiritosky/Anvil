import AnvilAI
import AnvilKit
import AnvilUI
import SwiftUI

/// Die Wahl, wen ein einzelnes Werkzeug fragt.
public struct AITargetPicker: View {
    private let context: ToolContext
    private let tool: ToolIdentifier

    public init(context: ToolContext, tool: ToolIdentifier) {
        self.context = context
        self.tool = tool
    }

    public var body: some View {
        InspectorSection(
            "Modell",
            systemImage: "sparkles",
            footnote: "Gilt nur für dieses Werkzeug. „Nur on-device\" in den Einstellungen überstimmt die Wahl hier — was den Mac nicht verlassen soll, verlässt ihn auch für ein einzelnes Werkzeug nicht."
        ) {
            let shown = names
            ChipPicker(
                selection: context.settings.bind(SettingKey<AITarget>.aiTarget(for: tool.rawValue)),
                options: AITarget.allCases,
                tone: .ai,
                title: { shown[$0] ?? $0.title }
            )
        }
    }

    /// „Agent" allein sagt niemandem, dass Claude Code gemeint ist.
    private var names: [AITarget: String] {
        [
            .standard: AITarget.standard.title,
            .onDevice: AITarget.onDevice.title,
            .agent: context.settings[.cliAgent].title,
            .remote: context.settings[.remoteConfiguration].presetName
        ]
    }
}
