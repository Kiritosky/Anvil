import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("JSON lesen und schreiben")
struct StructuredJSONTests {
    /// Der Grund, warum hier ein eigener Leser steht: `JSONSerialization`
    /// gäbe ein Wörterbuch zurück, also eine Reihenfolge nach Zufall.
    @Test
    func theKeyOrderSurvives() throws {
        let value = try StructuredValue.json(parsing: #"{"z": 1, "a": 2, "m": 3}"#)
        #expect(value.pairs?.map(\.key) == ["z", "a", "m"])
        #expect(value.jsonText.contains("\"z\": 1"))
        // Und in der Ausgabe steht z immer noch vorn.
        let text = value.jsonText
        #expect(text.range(of: "\"z\"")!.lowerBound < text.range(of: "\"a\"")!.lowerBound)
    }

    @Test
    func everyKindOfValueIsRead() throws {
        let value = try StructuredValue.json(
            parsing: #"{"t": "x", "n": 1.5, "b": true, "z": null, "l": [1, 2], "o": {"k": "v"}}"#
        )
        let pairs = try #require(value.pairs)
        #expect(pairs[0].value == .string("x"))
        #expect(pairs[1].value == .number(1.5))
        #expect(pairs[2].value == .boolean(true))
        #expect(pairs[3].value == .null)
        #expect(pairs[4].value == .array([.number(1), .number(2)]))
        #expect(pairs[5].value == .object([.init("k", .string("v"))]))
    }

    @Test
    func escapesAreUnderstoodAndWrittenBack() throws {
        let value = try StructuredValue.json(parsing: #"{"a": "Zeile\nZeile\t\"x\"ä"}"#)
        #expect(value.pairs?[0].value == .string("Zeile\nZeile\t\"x\"ä"))
        #expect(value.jsonText.contains(#"\n"#))
    }

    @Test
    func emptyContainersStayOnOneLine() throws {
        let value = try StructuredValue.json(parsing: #"{"a": [], "b": {}}"#)
        #expect(value.jsonText == "{\n  \"a\": [],\n  \"b\": {}\n}")
    }

    /// Ganze Zahlen sollen ganze Zahlen bleiben — `1` und nicht `1.0`.
    @Test
    func wholeNumbersHaveNoDecimalPoint() throws {
        let value = try StructuredValue.json(parsing: #"{"a": 1, "b": 1.5, "c": -3}"#)
        #expect(value.jsonText.contains("\"a\": 1,"))
        #expect(value.jsonText.contains("\"b\": 1.5"))
        #expect(value.jsonText.contains("\"c\": -3"))
    }

    @Test(arguments: [
        "", "{", "[1,", #"{"a" 1}"#, #"{a: 1}"#, "{} extra", "nichts"
    ])
    func brokenJSONThrows(_ text: String) {
        #expect(throws: AnvilError.self) { try StructuredValue.json(parsing: text) }
    }

    @Test
    func aRoundTripChangesNothing() throws {
        let source = #"{"a":[1,{"b":"c"}],"d":null}"#
        let once = try StructuredValue.json(parsing: source)
        let twice = try StructuredValue.json(parsing: once.jsonText)
        #expect(once == twice)
    }
}

@Suite("YAML lesen")
struct StructuredYAMLTests {
    @Test
    func mappingsNestByIndentation() throws {
        let value = try StructuredValue.yaml(parsing: """
        name: Anvil
        fenster:
          breite: 900
          hoch: true
        """)
        let pairs = try #require(value.pairs)
        #expect(pairs[0].key == "name")
        #expect(pairs[0].value == .string("Anvil"))
        let inner = try #require(pairs[1].value.pairs)
        #expect(inner[0].value == .number(900))
        #expect(inner[1].value == .boolean(true))
    }

    @Test
    func sequencesBecomeArrays() throws {
        let value = try StructuredValue.yaml(parsing: """
        werkzeuge:
          - Tabellen
          - Netzrechner
        """)
        #expect(value.pairs?[0].value == .array([.string("Tabellen"), .string("Netzrechner")]))
    }

    /// Der Fall, an dem eine naive Zerlegung scheitert: Der Strich und der
    /// Schlüssel stehen in derselben Zeile, die Fortsetzung darunter.
    @Test
    func aSequenceOfMappingsIsRead() throws {
        let value = try StructuredValue.yaml(parsing: """
        server:
          - name: eins
            port: 80
          - name: zwei
            port: 443
        """)
        let list = try #require(value.pairs?[0].value.elements)
        #expect(list.count == 2)
        #expect(list[0].pairs?[0].value == .string("eins"))
        #expect(list[0].pairs?[1].value == .number(80))
        #expect(list[1].pairs?[1].value == .number(443))
    }

    @Test
    func commentsAndDocumentMarkersFallAway() throws {
        let value = try StructuredValue.yaml(parsing: """
        ---
        # Ein Kommentar
        a: 1  # noch einer
        """)
        #expect(value.pairs?.count == 1)
        #expect(value.pairs?[0].value == .number(1))
    }

    /// Ein `#` in Anführungszeichen ist kein Kommentar.
    @Test
    func aHashInsideQuotesStays() throws {
        // Zwei Rauten als Begrenzer: in #"…"# beendet die Folge "# die
        // Zeichenkette, und genau die steht hier mitten im Text.
        let value = try StructuredValue.yaml(parsing: ##"farbe: "#3A7BD5""##)
        #expect(value.pairs?[0].value == .string("#3A7BD5"))
    }

    /// `zeit: 12:30` darf nicht am zweiten Doppelpunkt zerfallen.
    @Test
    func onlyTheFirstColonWithASpaceAfterItSplits() throws {
        let value = try StructuredValue.yaml(parsing: "zeit: 12:30")
        #expect(value.pairs?[0].key == "zeit")
        #expect(value.pairs?[0].value == .string("12:30"))
    }

    @Test
    func inlineListsAndMappingsAreRead() throws {
        let value = try StructuredValue.yaml(parsing: """
        zahlen: [1, 2, 3]
        punkt: {x: 1, y: 2}
        tief: [1, [2, 3]]
        """)
        let pairs = try #require(value.pairs)
        #expect(pairs[0].value == .array([.number(1), .number(2), .number(3)]))
        #expect(pairs[1].value.pairs?.count == 2)
        #expect(pairs[2].value.elements?.count == 2)
    }

    @Test
    func quotesKeepTheirContentAsText() throws {
        let value = try StructuredValue.yaml(parsing: """
        a: "12"
        b: '12'
        c: 12
        """)
        let pairs = try #require(value.pairs)
        #expect(pairs[0].value == .string("12"))
        #expect(pairs[1].value == .string("12"))
        #expect(pairs[2].value == .number(12))
    }

    /// Ein Blocktext ist Text: Kommentarzeichen und Striche darin bleiben
    /// stehen.
    @Test
    func blockTextKeepsItsLines() throws {
        let value = try StructuredValue.yaml(parsing: """
        skript: |
          echo eins
          # kein Kommentar
          - kein Listenpunkt
        danach: 1
        """)
        let pairs = try #require(value.pairs)
        #expect(pairs[0].value == .string("echo eins\n# kein Kommentar\n- kein Listenpunkt"))
        // Und danach geht die Struktur normal weiter.
        #expect(pairs[1].key == "danach")
        #expect(pairs[1].value == .number(1))
    }

    @Test
    func foldedBlockTextJoinsWithSpaces() throws {
        let value = try StructuredValue.yaml(parsing: """
        text: >
          eins
          zwei
        """)
        #expect(value.pairs?[0].value == .string("eins zwei"))
    }

    @Test
    func aTopLevelListIsAList() throws {
        let value = try StructuredValue.yaml(parsing: "- eins\n- zwei")
        #expect(value == .array([.string("eins"), .string("zwei")]))
    }

    @Test
    func nothingInIsNothingOut() throws {
        #expect(try StructuredValue.yaml(parsing: "") == .null)
        #expect(try StructuredValue.yaml(parsing: "# nur ein Kommentar") == .null)
    }
}

@Suite("YAML schreiben")
struct StructuredYAMLWritingTests {
    @Test
    func aRoundTripThroughYAMLChangesNothing() throws {
        let source = """
        {"name":"Anvil","fenster":{"breite":900,"hoch":true},
         "werkzeuge":["Tabellen","Netzrechner"],
         "server":[{"name":"eins","port":80},{"name":"zwei","port":443}]}
        """
        let json = try StructuredValue.json(parsing: source)
        let back = try StructuredValue.yaml(parsing: json.yamlText)
        #expect(back == json)
    }

    /// Was unangeführt als Zahl oder Wahrheitswert zurückkäme, muss angeführt
    /// werden — sonst ist es beim nächsten Lesen keins mehr.
    @Test
    func textThatLooksLikeSomethingElseGetsQuotes() throws {
        let value = StructuredValue.object([
            .init("a", .string("12")),
            .init("b", .string("true")),
            .init("c", .string("null")),
            .init("d", .string("einfach"))
        ])
        let text = value.yamlText
        #expect(text.contains("a: \"12\""))
        #expect(text.contains("b: \"true\""))
        #expect(text.contains("c: \"null\""))
        #expect(text.contains("d: einfach"))

        let back = try StructuredValue.yaml(parsing: text)
        #expect(back == value)
    }

    @Test
    func emptyContainersAreWrittenInline() {
        let value = StructuredValue.object([
            .init("a", .array([])),
            .init("b", .object([]))
        ])
        #expect(value.yamlText == "a: []\nb: {}")
    }
}

@Suite("TOML lesen")
struct StructuredTOMLTests {
    @Test
    func keysAndTablesBecomeNestedObjects() throws {
        let value = try StructuredValue.toml(parsing: """
        titel = "Anvil"

        [fenster]
        breite = 900
        hoch = true
        """)
        let pairs = try #require(value.pairs)
        #expect(pairs[0].key == "titel")
        #expect(pairs[0].value == .string("Anvil"))
        #expect(pairs[1].value.pairs?[0].value == .number(900))
    }

    /// `[a.b.c]` setzt `a` und `a.b` voraus, ohne dass sie je dastanden.
    @Test
    func aDeepTableCreatesEverythingAboveIt() throws {
        let value = try StructuredValue.toml(parsing: "[a.b.c]\nx = 1")
        let a = try #require(value.pairs?[0].value.pairs)
        let b = try #require(a[0].value.pairs)
        #expect(b[0].key == "c")
        #expect(b[0].value.pairs?[0].value == .number(1))
    }

    @Test
    func aRowOfTablesBecomesAnArray() throws {
        let value = try StructuredValue.toml(parsing: """
        [[server]]
        name = "eins"

        [[server]]
        name = "zwei"
        """)
        let rows = try #require(value.pairs?[0].value.elements)
        #expect(rows.count == 2)
        #expect(rows[0].pairs?[0].value == .string("eins"))
        #expect(rows[1].pairs?[0].value == .string("zwei"))
    }

    @Test
    func dottedKeysNestToo() throws {
        let value = try StructuredValue.toml(parsing: "a.b = 1")
        #expect(value.pairs?[0].value.pairs?[0].value == .number(1))
    }

    @Test
    func listsAndInlineTablesAreRead() throws {
        let value = try StructuredValue.toml(parsing: """
        zahlen = [1, 2, 3]
        punkt = { x = 1, y = 2 }
        """)
        let pairs = try #require(value.pairs)
        #expect(pairs[0].value == .array([.number(1), .number(2), .number(3)]))
        #expect(pairs[1].value.pairs?.count == 2)
    }

    @Test
    func underscoresInNumbersAreSeparators() throws {
        let value = try StructuredValue.toml(parsing: "gross = 1_000_000")
        #expect(value.pairs?[0].value == .number(1_000_000))
    }

    /// TOML kennt fünf Zeitformate, JSON keins. Text zu bleiben ist die
    /// einzige Fassung, die nichts verliert.
    @Test
    func datesStayText() throws {
        let value = try StructuredValue.toml(parsing: "wann = 2026-08-10T21:00:00Z")
        #expect(value.pairs?[0].value == .string("2026-08-10T21:00:00Z"))
    }

    @Test
    func commentsFallAway() throws {
        let value = try StructuredValue.toml(parsing: "# oben\na = 1 # daneben")
        #expect(value.pairs?.count == 1)
        #expect(value.pairs?[0].value == .number(1))
    }

    @Test
    func aKeyTwiceIsAnError() {
        #expect(throws: AnvilError.self) {
            try StructuredValue.toml(parsing: "a = 1\na = 2")
        }
    }

    @Test(arguments: ["[unfertig", "a", "[[reihe]"])
    func brokenTOMLThrows(_ text: String) {
        #expect(throws: AnvilError.self) { try StructuredValue.toml(parsing: text) }
    }
}

@Suite("TOML schreiben")
struct StructuredTOMLWritingTests {
    /// Alles hinter einer `[tabelle]`-Zeile gehört zu dieser Tabelle. Ein
    /// Skalar, der nach einer Untertabelle stünde, landete beim nächsten Lesen
    /// darin.
    @Test
    func plainValuesComeBeforeTables() {
        let value = StructuredValue.object([
            .init("tabelle", .object([.init("x", .number(1))])),
            .init("einfach", .number(2))
        ])
        let text = value.tomlText
        let plainLine = text.range(of: "einfach = 2")
        let tableLine = text.range(of: "[tabelle]")
        #expect(plainLine != nil)
        #expect(tableLine != nil)
        if let plainLine, let tableLine {
            #expect(plainLine.lowerBound < tableLine.lowerBound)
        }
    }

    @Test
    func aRoundTripThroughTOMLChangesNothing() throws {
        let source = """
        titel = "Anvil"
        zahlen = [1, 2, 3]

        [fenster]
        breite = 900

        [[server]]
        name = "eins"

        [[server]]
        name = "zwei"
        """
        let value = try StructuredValue.toml(parsing: source)
        let back = try StructuredValue.toml(parsing: value.tomlText)
        #expect(back == value)
    }

    @Test
    func anArrayOfObjectsBecomesARowOfTables() {
        let value = StructuredValue.object([
            .init("server", .array([
                .object([.init("name", .string("eins"))]),
                .object([.init("name", .string("zwei"))])
            ]))
        ])
        #expect(value.tomlText.contains("[[server]]"))
    }
}

@Suite("Format raten")
struct StructuredDetectionTests {
    @Test
    func theShapeOfTheFirstLineDecides() {
        #expect(StructuredToolView.detect(#"{"a": 1}"#) == .json)
        #expect(StructuredToolView.detect("[1, 2, 3]") == .json)
        #expect(StructuredToolView.detect("[server]\nport = 80") == .toml)
        #expect(StructuredToolView.detect("a = 1") == .toml)
        #expect(StructuredToolView.detect("a: 1") == .yaml)
        #expect(StructuredToolView.detect("- eins\n- zwei") == .yaml)
    }

    /// Ein Kommentar oben ändert nichts daran, was darunter steht.
    @Test
    func commentsAreSkippedWhenGuessing() {
        #expect(StructuredToolView.detect("# Notiz\nport = 80") == .toml)
        #expect(StructuredToolView.detect("# Notiz\nport: 80") == .yaml)
    }
}
