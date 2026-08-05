import AnvilKit
import Foundation

/// A tool that is nothing but a prompt.
///
/// `Codable` on purpose: the built-in AI tools and the ones a user drops into
/// `~/Library/Application Support/Anvil/Tools` are the *same type*, loaded by
/// the same engine. That is what makes "add your own tool" a file rather than a
/// plug-in API.
public struct AIPromptTool: Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    /// Matches a ``ToolCategory`` identifier; unknown values land in "Eigene".
    public var categoryID: String
    public var keywords: [String]

    /// The model's standing role.
    public var instructions: String
    /// The per-run prompt. `{{input}}` is replaced with the input pane's text,
    /// `{{option:id}}` with the value of the option of that id.
    public var promptTemplate: String
    public var options: [AIPromptOption]

    public var temperature: Double?
    public var inputPlaceholder: String
    public var isMonospacedInput: Bool
    /// Where the input comes from.
    public var inputSource: AIPromptInputSource

    public init(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String,
        categoryID: String = ToolCategory.everyday.id,
        keywords: [String] = [],
        instructions: String,
        promptTemplate: String = "{{input}}",
        options: [AIPromptOption] = [],
        temperature: Double? = 0.3,
        inputPlaceholder: String = "Text hier einfügen …",
        isMonospacedInput: Bool = false,
        inputSource: AIPromptInputSource = .text
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.categoryID = categoryID
        self.keywords = keywords
        self.instructions = instructions
        self.promptTemplate = promptTemplate
        self.options = options
        self.temperature = temperature
        self.inputPlaceholder = inputPlaceholder
        self.isMonospacedInput = isMonospacedInput
        self.inputSource = inputSource
    }

    public var category: ToolCategory {
        ToolCategory.builtIn.first { $0.id == categoryID } ?? .custom
    }

    public func metadata(identifier: ToolIdentifier? = nil) -> ToolMetadata {
        ToolMetadata(
            id: identifier ?? ToolIdentifier(id),
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            category: category,
            keywords: keywords,
            requirements: inputSource == .gitDiff ? [.languageModel, .git] : [.languageModel]
        )
    }

    /// Fills the template with the input and the chosen option values.
    public func buildPrompt(input: String, optionValues: [String: String]) -> String {
        var prompt = promptTemplate.replacingOccurrences(of: "{{input}}", with: input)
        for option in options {
            let value = optionValues[option.id] ?? option.defaultValue
            prompt = prompt.replacingOccurrences(of: "{{option:\(option.id)}}", with: value)
        }
        return prompt
    }

    /// Fills the same placeholders in the instructions, so an option can change
    /// the model's role rather than just the prompt.
    public func buildInstructions(optionValues: [String: String]) -> String {
        var result = instructions
        for option in options {
            let value = optionValues[option.id] ?? option.defaultValue
            result = result.replacingOccurrences(of: "{{option:\(option.id)}}", with: value)
        }
        return result
    }
}

/// Where a prompt tool's input comes from.
public enum AIPromptInputSource: String, Codable, Sendable {
    /// The user types or pastes it.
    case text
    /// `git diff --staged` from a folder the user picks.
    case gitDiff
}

/// A knob shown in the tool's inspector.
public struct AIPromptOption: Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case choice
        case text
        case toggle
    }

    public var id: String
    public var label: String
    public var kind: Kind
    /// For ``Kind/choice``.
    public var choices: [String]
    public var defaultValue: String
    public var help: String?

    public init(
        id: String,
        label: String,
        kind: Kind = .choice,
        choices: [String] = [],
        defaultValue: String = "",
        help: String? = nil
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.choices = choices
        self.defaultValue = defaultValue.isEmpty ? (choices.first ?? "") : defaultValue
        self.help = help
    }
}
