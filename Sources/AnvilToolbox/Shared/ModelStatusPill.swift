import AnvilAI
import AnvilUI
import SwiftUI

/// Shows which model is answering, and whether it is doing so on this Mac.
public struct ModelStatusPill: View {
    @Environment(AIRouter.self) private var router: AIRouter?

    public init() {}

    public var body: some View {
        if let router {
            StatusPill(
                .resolved(label(for: router)),
                systemImage: router.activeRunsOnDevice ? "laptopcomputer" : "cloud",
                tone: tone(for: router)
            )
            .anvilHelp(verbatim: router.statusSummary)
        }
    }

    private func label(for router: AIRouter) -> String {
        guard router.availability.isAvailable else { return "Kein Modell" }
        return router.activeRunsOnDevice ? "On-Device" : router.activeProviderName
    }

    private func tone(for router: AIRouter) -> AnvilTone {
        guard router.availability.isAvailable else { return .warning }
        return router.activeRunsOnDevice ? .ai : .info
    }
}
