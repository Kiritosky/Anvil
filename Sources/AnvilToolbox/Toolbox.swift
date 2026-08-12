import AnvilKit

/// Was Anvil mitbringt.
///
/// Die Liste steht hier und nicht in der App-Shell, obwohl die Reihenfolge die
/// der Seitenleiste ist: Sonst wüsste nur die Shell, welche Sammlungen es
/// überhaupt gibt — und damit ließe sich der Werkzeugkasten als Ganzes nirgends
/// prüfen. Genau das ist aber die einzige Stelle, an der doppelte Kennungen und
/// leere Titel auffallen, ohne dass jemand die App startet.
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
