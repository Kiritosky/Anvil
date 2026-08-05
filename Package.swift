// swift-tools-version: 6.0
import PackageDescription

// Anvil is a modular macOS toolbox. The package is split so that the
// extensibility core (AnvilKit) knows nothing about AI, speech or the app shell,
// and every layer above it can be replaced or extended independently.
let package = Package(
    name: "Anvil",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Anvil", targets: ["AnvilApp"]),
        .library(name: "AnvilKit", targets: ["AnvilKit"]),
        .library(name: "AnvilUI", targets: ["AnvilUI"]),
        .library(name: "AnvilAI", targets: ["AnvilAI"]),
        .library(name: "AnvilSpeech", targets: ["AnvilSpeech"]),
        .library(name: "AnvilToolbox", targets: ["AnvilToolbox"])
    ],
    targets: [
        // Extensibility core: tool model, registry, storage, small utilities.
        .target(
            name: "AnvilKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Design system: tokens, base layouts, shared SwiftUI components.
        // Every tool view is assembled from these so the app looks like one app.
        .target(
            name: "AnvilUI",
            dependencies: ["AnvilKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Language-model abstraction: on-device Foundation Models + remote providers.
        .target(
            name: "AnvilAI",
            dependencies: ["AnvilKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Speech capture and transcription built on SpeechAnalyzer.
        .target(
            name: "AnvilSpeech",
            dependencies: ["AnvilKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The actual tools plus the generic tool engines they are built from.
        .target(
            name: "AnvilToolbox",
            dependencies: ["AnvilKit", "AnvilUI", "AnvilAI", "AnvilSpeech"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Thin app shell: window, sidebar, command palette, settings, menu bar.
        .executableTarget(
            name: "AnvilApp",
            dependencies: ["AnvilKit", "AnvilUI", "AnvilAI", "AnvilSpeech", "AnvilToolbox"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AnvilKitTests",
            dependencies: ["AnvilKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AnvilToolboxTests",
            dependencies: ["AnvilToolbox", "AnvilKit", "AnvilAI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
