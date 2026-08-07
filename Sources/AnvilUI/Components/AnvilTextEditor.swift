import SwiftUI

/// The app's editable text area.
///
/// A plain `TextEditor` has no placeholder, no border that matches the rest of
/// the app, and no focus treatment. This adds all three and nothing else.
public struct AnvilTextEditor: View {
    @Binding private var text: String
    private let placeholder: LocalizedStringKey?
    private let isMonospaced: Bool
    private let isEditable: Bool

    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        placeholder: LocalizedStringKey? = nil,
        isMonospaced: Bool = false,
        isEditable: Bool = true
    ) {
        self._text = text
        self.placeholder = placeholder
        self.isMonospaced = isMonospaced
        self.isEditable = isEditable
    }

    public var body: some View {
        TextEditor(text: $text)
            .font(isMonospaced ? AnvilFont.mono : AnvilFont.body)
            .lineSpacing(isMonospaced ? 2 : 3)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .padding(.horizontal, AnvilSpacing.md - 4)
            .padding(.vertical, AnvilSpacing.sm)
            .focused($isFocused)
            .disabled(!isEditable)
            .overlay(alignment: .topLeading) {
                if text.isEmpty, let placeholder {
                    Text(placeholder)
                        .font(isMonospaced ? AnvilFont.mono : AnvilFont.body)
                        .foregroundStyle(AnvilColor.textTertiary)
                        .padding(.horizontal, AnvilSpacing.md)
                        .padding(.vertical, AnvilSpacing.sm + 1)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(AnvilMotion.quick, value: isFocused)
    }
}

/// Read-only, selectable, scrollable text.
///
/// Used for results — including ones still streaming in — where an editor would
/// wrongly suggest the text is meant to be typed into.
public struct AnvilTextView: View {
    private let text: String
    private let isMonospaced: Bool
    /// Keeps the view pinned to the bottom while new text streams in.
    private let followsTail: Bool

    private static let tailAnchor = "anvil.text.tail"

    public init(_ text: String, isMonospaced: Bool = false, followsTail: Bool = false) {
        self.text = text
        self.isMonospaced = isMonospaced
        self.followsTail = followsTail
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text)
                        .font(isMonospaced ? AnvilFont.mono : AnvilFont.body)
                        .lineSpacing(isMonospaced ? 2 : 3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear
                        .frame(height: 1)
                        .id(Self.tailAnchor)
                }
                .padding(.horizontal, AnvilSpacing.md)
                .padding(.vertical, AnvilSpacing.sm)
            }
            .onChange(of: text) { _, _ in
                guard followsTail else { return }
                withAnimation(AnvilMotion.quick) {
                    proxy.scrollTo(Self.tailAnchor, anchor: .bottom)
                }
            }
        }
    }
}

/// A single-line field styled like the rest of the app.
public struct AnvilTextField: View {
    @Binding private var text: String
    private let placeholder: LocalizedStringKey
    private let isMonospaced: Bool
    private let isSecure: Bool

    public init(
        text: Binding<String>,
        placeholder: LocalizedStringKey = "",
        isMonospaced: Bool = false,
        isSecure: Bool = false
    ) {
        self._text = text
        self.placeholder = placeholder
        self.isMonospaced = isMonospaced
        self.isSecure = isSecure
    }

    public var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(isMonospaced ? AnvilFont.monoSmall : AnvilFont.body)
        .padding(.horizontal, AnvilSpacing.sm)
        .frame(height: AnvilSize.controlHeight)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                .fill(AnvilColor.field)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                .strokeBorder(AnvilColor.border, lineWidth: AnvilSize.hairline)
        }
    }
}
