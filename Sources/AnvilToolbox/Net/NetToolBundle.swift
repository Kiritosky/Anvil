import AnvilKit
import SwiftUI

/// Werkzeuge fürs Netz.
public enum NetToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.net"
    public static let displayName = "Netz"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        [networkCalculator]
    }

    @MainActor
    private static var networkCalculator: ToolRegistration {
        let metadata = ToolMetadata(
            id: "net.subnet",
            title: "Netzrechner",
            subtitle: "CIDR rechnen, teilen, Adressen zuordnen",
            systemImage: "network",
            category: .coding,
            keywords: [
                "ip", "ipv4", "ipv6", "cidr", "subnetz", "subnet", "netzmaske",
                "maske", "netmask", "wildcard", "broadcast", "präfix", "prefix"
            ],
            acceptsText: true
        )

        return ToolRegistration(metadata: metadata) { context in
            NetToolView(context: context, metadata: metadata)
        }
    }
}
