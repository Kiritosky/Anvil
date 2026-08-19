import AnvilKit

/// Was Anvil mitbringt.
public enum Toolbox {
    public static let bundles: [any ToolBundle.Type] = [
        SpeechToolBundle.self,
        AIToolBundle.self,
        TextToolBundle.self,
        DevToolBundle.self,
        MarkdownToolBundle.self,
        TimeToolBundle.self,
        DataToolBundle.self,
        StructuredToolBundle.self,
        DiffToolBundle.self,
        GitToolBundle.self,
        NetToolBundle.self,
        SampleDataToolBundle.self,
        FileToolBundle.self,
        PDFToolBundle.self,
        EverydayToolBundle.self,
        ScreenshotToolBundle.self,
        SystemToolBundle.self
    ]
}
