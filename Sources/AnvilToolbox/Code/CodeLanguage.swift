import AnvilKit
import Foundation

/// Eine Programmiersprache, so weit Anvil sie zum Zählen kennen muss.
///
/// Erkannt wird an der Endung, nicht am Inhalt. Das ist die Regel, an die sich
/// jedes Werkzeug dieser Art hält — und es ist die einzige, die bei
/// zehntausend Dateien schnell genug bleibt.
public struct CodeLanguage: Sendable, Hashable, Identifiable {
    public let name: String
    /// Womit eine Zeile zum Kommentar wird.
    public let lineComments: [String]
    public let blockOpen: String?
    public let blockClose: String?

    public var id: String { name }

    public init(
        _ name: String,
        line: [String] = [],
        blockOpen: String? = nil,
        blockClose: String? = nil
    ) {
        self.name = name
        self.lineComments = line
        self.blockOpen = blockOpen
        self.blockClose = blockClose
    }

    // MARK: - Erkennen

    /// Die Sprache einer Datei — oder nichts, wenn Anvil sie nicht kennt.
    ///
    /// Was hier nicht steht, wird nicht mitgezählt. Das ist Absicht: Eine
    /// Zeile „Sonstiges: 412.000" entsteht sonst aus Wörterbüchern,
    /// Testdaten und minimierten Bibliotheken und macht die ganze Zahl
    /// wertlos.
    public static func of(path: String) -> CodeLanguage? {
        let name = path.components(separatedBy: "/").last ?? path
        if let byName = byFileName[name.lowercased()] { return byName }

        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        let ext = String(name[name.index(after: dot)...]).lowercased()
        return byExtension[ext]
    }

    /// Ordner, die nie mitgezählt werden.
    ///
    /// Fremder Code, gebaute Ergebnisse, heruntergeladene Abhängigkeiten: Wer
    /// wissen will, wie groß sein Projekt ist, meint nicht `node_modules`.
    /// Versteckte Ordner wie `.git` fallen schon beim Durchlaufen weg.
    public static let ignoredFolders: Set<String> = [
        "node_modules", "pods", "vendor", "vendors", "dist", "build",
        "deriveddata", "carthage", "packages", "third_party", "thirdparty",
        "bower_components", "target", "out", "bin", "obj", "coverage",
        "__pycache__", "site-packages", "migrations"
    ]

    /// Ob ein Pfad durch einen dieser Ordner läuft.
    public static func isIgnored(_ path: String) -> Bool {
        path.components(separatedBy: "/")
            .dropLast()
            .contains { ignoredFolders.contains($0.lowercased()) }
    }

    // MARK: - Die Liste

    static let byFileName: [String: CodeLanguage] = [
        "makefile": CodeLanguage("Make", line: ["#"]),
        "dockerfile": CodeLanguage("Dockerfile", line: ["#"]),
        "gemfile": CodeLanguage("Ruby", line: ["#"]),
        "podfile": CodeLanguage("Ruby", line: ["#"]),
        "rakefile": CodeLanguage("Ruby", line: ["#"]),
        "package.json": CodeLanguage("JSON"),
        "cmakelists.txt": CodeLanguage("CMake", line: ["#"])
    ]

    static let byExtension: [String: CodeLanguage] = {
        var table: [String: CodeLanguage] = [:]

        func add(_ language: CodeLanguage, _ extensions: [String]) {
            for ext in extensions { table[ext] = language }
        }

        let cStyle = ["//"]
        add(CodeLanguage("Swift", line: cStyle, blockOpen: "/*", blockClose: "*/"), ["swift"])
        add(
            CodeLanguage("Objective-C", line: cStyle, blockOpen: "/*", blockClose: "*/"),
            ["m", "mm", "h"]
        )
        add(CodeLanguage("C", line: cStyle, blockOpen: "/*", blockClose: "*/"), ["c"])
        add(
            CodeLanguage("C++", line: cStyle, blockOpen: "/*", blockClose: "*/"),
            ["cpp", "cc", "cxx", "hpp", "hh"]
        )
        add(CodeLanguage("C#", line: cStyle, blockOpen: "/*", blockClose: "*/"), ["cs"])
        add(CodeLanguage("Java", line: cStyle, blockOpen: "/*", blockClose: "*/"), ["java"])
        add(CodeLanguage("Kotlin", line: cStyle, blockOpen: "/*", blockClose: "*/"), ["kt", "kts"])
        add(CodeLanguage("Go", line: cStyle, blockOpen: "/*", blockClose: "*/"), ["go"])
        add(CodeLanguage("Rust", line: cStyle, blockOpen: "/*", blockClose: "*/"), ["rs"])
        add(
            CodeLanguage("JavaScript", line: cStyle, blockOpen: "/*", blockClose: "*/"),
            ["js", "mjs", "cjs", "jsx"]
        )
        add(
            CodeLanguage("TypeScript", line: cStyle, blockOpen: "/*", blockClose: "*/"),
            ["ts", "tsx", "mts"]
        )
        add(CodeLanguage("Dart", line: cStyle, blockOpen: "/*", blockClose: "*/"), ["dart"])
        add(CodeLanguage("PHP", line: ["//", "#"], blockOpen: "/*", blockClose: "*/"), ["php"])
        add(CodeLanguage("Scala", line: cStyle, blockOpen: "/*", blockClose: "*/"), ["scala"])
        add(CodeLanguage("Groovy", line: cStyle, blockOpen: "/*", blockClose: "*/"), ["groovy"])
        add(CodeLanguage("CSS", line: [], blockOpen: "/*", blockClose: "*/"), ["css"])
        add(CodeLanguage("Sass", line: cStyle, blockOpen: "/*", blockClose: "*/"), ["scss", "sass"])
        add(CodeLanguage("Metal", line: cStyle, blockOpen: "/*", blockClose: "*/"), ["metal"])
        add(CodeLanguage("GLSL", line: cStyle, blockOpen: "/*", blockClose: "*/"), ["glsl", "frag", "vert"])

        add(CodeLanguage("Python", line: ["#"]), ["py", "pyi"])
        add(CodeLanguage("Ruby", line: ["#"]), ["rb"])
        add(CodeLanguage("Shell", line: ["#"]), ["sh", "bash", "zsh", "fish"])
        add(CodeLanguage("Perl", line: ["#"]), ["pl", "pm"])
        add(CodeLanguage("R", line: ["#"]), ["r"])
        add(CodeLanguage("YAML", line: ["#"]), ["yml", "yaml"])
        add(CodeLanguage("TOML", line: ["#"]), ["toml"])
        add(CodeLanguage("Makefile", line: ["#"]), ["mk"])
        add(CodeLanguage("Elixir", line: ["#"]), ["ex", "exs"])
        add(CodeLanguage("Lua", line: ["--"], blockOpen: "--[[", blockClose: "]]"), ["lua"])
        add(CodeLanguage("SQL", line: ["--"], blockOpen: "/*", blockClose: "*/"), ["sql"])
        add(CodeLanguage("Haskell", line: ["--"], blockOpen: "{-", blockClose: "-}"), ["hs"])

        add(CodeLanguage("HTML", line: [], blockOpen: "<!--", blockClose: "-->"), ["html", "htm"])
        add(CodeLanguage("XML", line: [], blockOpen: "<!--", blockClose: "-->"), ["xml", "plist", "xib", "storyboard"])
        add(CodeLanguage("Markdown", line: [], blockOpen: "<!--", blockClose: "-->"), ["md", "markdown"])
        add(CodeLanguage("Vue", line: [], blockOpen: "<!--", blockClose: "-->"), ["vue"])
        add(CodeLanguage("JSON"), ["json"])

        return table
    }()

    /// Alle Sprachen, die Anvil kennt — für die Anzeige „was gezählt wird".
    public static var all: [String] {
        Set(byExtension.values.map(\.name) + byFileName.values.map(\.name)).sorted()
    }
}
