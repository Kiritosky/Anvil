import AnvilKit
import Foundation

/// The prompt tools Anvil ships with.
public enum AIPromptCatalog {
    public static var all: [AIPromptTool] {
        coding + everyday
    }

    /// Shared rules. Prompt tools are for getting work done, not for chatting,
    /// and the single most common annoyance is a model that answers with
    /// "Sure! Here's your…" instead of the thing itself.
    private static let baseRules = """
    Antworte ausschließlich mit dem Ergebnis. Keine Einleitung, kein Kommentar \
    davor oder danach, keine Rückfragen. Antworte in der Sprache der Eingabe, \
    sofern nicht ausdrücklich etwas anderes verlangt wird.
    """

    // MARK: - Coding

    public static var coding: [AIPromptTool] {
        [
            AIPromptTool(
                id: "ai.commit",
                title: "Commit-Message",
                subtitle: "Aus dem Diff eine saubere Message",
                systemImage: "arrow.triangle.branch",
                categoryID: ToolCategory.coding.id,
                keywords: ["commit", "git", "message", "conventional commits"],
                instructions: """
                Du schreibst Commit-Messages nach Conventional Commits für einen Diff.

                \(baseRules)

                Format:
                - Erste Zeile: "typ(bereich): beschreibung" — Imperativ, höchstens 72 Zeichen, kein Punkt am Ende.
                - Typen: feat, fix, refactor, docs, test, chore, perf, build, ci.
                - Bei nicht offensichtlichen Änderungen: Leerzeile, dann Fließtext, der das Warum erklärt, \
                nicht das Was — das steht im Diff.
                - Stil: {{option:style}}
                """,
                promptTemplate: "Diff:\n\n{{input}}",
                options: [
                    AIPromptOption(
                        id: "style",
                        label: "Umfang",
                        choices: ["nur Betreffzeile", "Betreff + kurzer Text", "ausführlich"],
                        defaultValue: "Betreff + kurzer Text"
                    )
                ],
                temperature: 0.2,
                inputPlaceholder: "git diff …",
                isMonospacedInput: true,
                inputSource: .gitDiff
            ),

            AIPromptTool(
                id: "ai.explain",
                title: "Code erklären",
                subtitle: "Was macht dieser Code — und warum",
                systemImage: "text.book.closed",
                categoryID: ToolCategory.coding.id,
                keywords: ["code", "erklären", "explain", "verstehen", "review"],
                instructions: """
                Du erklärst fremden Code so, dass jemand ihn danach ändern kann.

                \(baseRules)

                Vorgehen:
                1. Ein Satz: was der Code tut.
                2. Der Ablauf in wenigen Schritten.
                3. Die nicht offensichtlichen Stellen: Randfälle, Annahmen, Fallstricke.
                Detailgrad: {{option:depth}}
                """,
                options: [
                    AIPromptOption(
                        id: "depth",
                        label: "Detailgrad",
                        choices: ["kurz", "normal", "zeilenweise"],
                        defaultValue: "normal"
                    )
                ],
                temperature: 0.2,
                inputPlaceholder: "Code hier einfügen …",
                isMonospacedInput: true
            ),

            AIPromptTool(
                id: "ai.review",
                title: "Code-Review",
                subtitle: "Fehler, Risiken, Verbesserungen",
                systemImage: "checklist",
                categoryID: ToolCategory.coding.id,
                keywords: ["review", "bugs", "qualität", "refactor", "prüfen"],
                instructions: """
                Du prüfst Code wie eine erfahrene Kollegin im Review.

                \(baseRules)

                Regeln:
                - Sortiere nach Schwere: erst echte Fehler, dann Risiken, dann Stil.
                - Ein Punkt pro Zeile, beginnend mit "- ".
                - Zu jedem Punkt: was ist das Problem und was ist die konkrete Änderung.
                - Erfinde keine Probleme. Wenn nichts Ernstes drin ist, sag das in einem Satz.
                - Schwerpunkt: {{option:focus}}
                """,
                options: [
                    AIPromptOption(
                        id: "focus",
                        label: "Schwerpunkt",
                        choices: ["alles", "Korrektheit", "Sicherheit", "Performance", "Lesbarkeit"],
                        defaultValue: "alles"
                    )
                ],
                temperature: 0.2,
                isMonospacedInput: true
            ),

            AIPromptTool(
                id: "ai.tests",
                title: "Tests schreiben",
                subtitle: "Testfälle zu vorhandenem Code",
                systemImage: "testtube.2",
                categoryID: ToolCategory.coding.id,
                keywords: ["test", "unit test", "xctest", "swift testing", "spec"],
                instructions: """
                Du schreibst Tests für vorhandenen Code.

                \(baseRules)

                Regeln:
                - Framework: {{option:framework}}.
                - Deck den Normalfall, die Randfälle und die Fehlerfälle ab.
                - Testnamen sagen, was erwartet wird.
                - Nur Testcode, keine Erklärung drumherum.
                """,
                options: [
                    AIPromptOption(
                        id: "framework",
                        label: "Framework",
                        choices: ["Swift Testing", "XCTest", "wie im Code erkennbar"],
                        defaultValue: "wie im Code erkennbar"
                    )
                ],
                temperature: 0.2,
                isMonospacedInput: true
            ),

            AIPromptTool(
                id: "ai.regex",
                title: "Regex bauen",
                subtitle: "Beschreibung rein, Ausdruck raus",
                systemImage: "asterisk",
                categoryID: ToolCategory.coding.id,
                keywords: ["regex", "regulärer ausdruck", "pattern", "muster"],
                instructions: """
                Du baust reguläre Ausdrücke.

                \(baseRules)

                Antwortformat:
                1. Der Ausdruck allein in einer Zeile.
                2. Leerzeile.
                3. Die Bestandteile, einer pro Zeile, jeweils "teil — bedeutung".
                4. Leerzeile, dann zwei Beispiele, die passen, und zwei, die nicht passen.
                Dialekt: {{option:flavor}}
                """,
                options: [
                    AIPromptOption(
                        id: "flavor",
                        label: "Dialekt",
                        choices: ["ICU (Swift/NSRegularExpression)", "PCRE", "JavaScript", "Python"],
                        defaultValue: "ICU (Swift/NSRegularExpression)"
                    )
                ],
                temperature: 0.2,
                inputPlaceholder: "Beschreib, was gefunden werden soll …"
            ),

            AIPromptTool(
                id: "ai.shell",
                title: "Shell-Befehl",
                subtitle: "Beschreibung in ein Kommando",
                systemImage: "terminal",
                categoryID: ToolCategory.coding.id,
                keywords: ["shell", "terminal", "bash", "zsh", "kommando", "cli"],
                instructions: """
                Du übersetzt Beschreibungen in Shell-Befehle für macOS (zsh).

                \(baseRules)

                Antwortformat:
                1. Der Befehl allein in einer Zeile.
                2. Leerzeile.
                3. Je eine Zeile pro Option: "-x — wofür".
                - Bevorzuge Werkzeuge, die auf macOS vorhanden sind.
                - Wenn der Befehl Daten löscht oder überschreibt, setze als letzte Zeile eine \
                Warnung, die mit "Achtung:" beginnt.
                """,
                temperature: 0.2,
                inputPlaceholder: "Was soll der Befehl tun?"
            ),

            AIPromptTool(
                id: "ai.error",
                title: "Fehler verstehen",
                subtitle: "Stacktrace oder Compiler-Meldung deuten",
                systemImage: "exclamationmark.triangle",
                categoryID: ToolCategory.coding.id,
                keywords: ["fehler", "error", "stacktrace", "crash", "compiler", "debug"],
                instructions: """
                Du erklärst Fehlermeldungen und Stacktraces.

                \(baseRules)

                Antwortformat:
                1. Ein Satz: was schiefgeht.
                2. "Wahrscheinliche Ursache:" — die plausibelste, nicht alle denkbaren.
                3. "Nächster Schritt:" — was konkret zu tun ist.
                Wenn die Meldung für eine sichere Aussage nicht reicht, sag genau, welche \
                Information fehlt.
                """,
                temperature: 0.2,
                inputPlaceholder: "Fehlermeldung oder Stacktrace …",
                isMonospacedInput: true
            ),

            AIPromptTool(
                id: "ai.naming",
                title: "Benennung",
                subtitle: "Bessere Namen für Dinge im Code",
                systemImage: "character.cursor.ibeam",
                categoryID: ToolCategory.coding.id,
                keywords: ["naming", "benennung", "variable", "funktion", "umbenennen"],
                instructions: """
                Du schlägst Namen für Code-Bezeichner vor.

                \(baseRules)

                Regeln:
                - Fünf Vorschläge, bester zuerst, einer pro Zeile: "name — warum".
                - Sprache der Namen: {{option:language}}. Konvention: {{option:convention}}.
                - Namen sagen, was die Sache ist oder tut, nicht wie sie implementiert ist.
                """,
                options: [
                    AIPromptOption(
                        id: "language",
                        label: "Sprache der Namen",
                        choices: ["Englisch", "Deutsch"],
                        defaultValue: "Englisch"
                    ),
                    AIPromptOption(
                        id: "convention",
                        label: "Konvention",
                        choices: ["camelCase", "PascalCase", "snake_case", "kebab-case"],
                        defaultValue: "camelCase"
                    )
                ],
                temperature: 0.5,
                inputPlaceholder: "Was benennt werden soll, plus Kontext …"
            ),

            AIPromptTool(
                id: "ai.doccomment",
                title: "Doku-Kommentar",
                subtitle: "Dokumentation zu einer Funktion",
                systemImage: "text.quote",
                categoryID: ToolCategory.coding.id,
                keywords: ["dokumentation", "kommentar", "docc", "javadoc", "docstring"],
                instructions: """
                Du schreibst Doku-Kommentare für Code.

                \(baseRules)

                Regeln:
                - Format: {{option:format}}.
                - Erster Satz: was die Sache tut, in einer Zeile.
                - Danach nur, was nicht schon im Code steht: Warum, Randfälle, Annahmen, Fehlerfälle.
                - Keine Wiederholung der Signatur in Worten.
                """,
                options: [
                    AIPromptOption(
                        id: "format",
                        label: "Format",
                        choices: ["Swift DocC (///)", "Javadoc", "Python Docstring", "JSDoc"],
                        defaultValue: "Swift DocC (///)"
                    )
                ],
                temperature: 0.2,
                isMonospacedInput: true
            ),

            AIPromptTool(
                id: "ai.sql",
                title: "SQL",
                subtitle: "Abfrage aus einer Beschreibung",
                systemImage: "cylinder.split.1x2",
                categoryID: ToolCategory.coding.id,
                keywords: ["sql", "query", "datenbank", "select", "join"],
                instructions: """
                Du schreibst SQL-Abfragen.

                \(baseRules)

                Regeln:
                - Dialekt: {{option:dialect}}.
                - Schlüsselwörter groß, ein Ausdruck pro Zeile, eingerückt.
                - Nach der Abfrage eine Leerzeile und je eine Zeile Erklärung pro Join oder \
                nicht offensichtlicher Bedingung.
                - Wenn das Schema nicht genannt wurde, nimm plausible Tabellennamen an und \
                schreib sie in eine Zeile "Angenommenes Schema:" darüber.
                """,
                options: [
                    AIPromptOption(
                        id: "dialect",
                        label: "Dialekt",
                        choices: ["PostgreSQL", "SQLite", "MySQL", "SQL Server"],
                        defaultValue: "PostgreSQL"
                    )
                ],
                temperature: 0.2,
                inputPlaceholder: "Was soll die Abfrage liefern?"
            )
        ]
    }

    // MARK: - Everyday

    public static var everyday: [AIPromptTool] {
        [
            AIPromptTool(
                id: "ai.rewrite",
                title: "Umschreiben",
                subtitle: "Gleicher Inhalt, anderer Ton",
                systemImage: "arrow.triangle.2.circlepath",
                categoryID: ToolCategory.everyday.id,
                keywords: ["umschreiben", "ton", "stil", "formulieren", "rewrite"],
                instructions: """
                Du schreibst Texte um, ohne ihren Inhalt zu verändern.

                \(baseRules)

                Vorgaben:
                - Ton: {{option:tone}}.
                - Länge: {{option:length}}.
                - Keine neuen Aussagen, keine weggelassenen Aussagen.
                """,
                options: [
                    AIPromptOption(
                        id: "tone",
                        label: "Ton",
                        choices: ["sachlich", "freundlich", "förmlich", "locker", "knapp"],
                        defaultValue: "sachlich"
                    ),
                    AIPromptOption(
                        id: "length",
                        label: "Länge",
                        choices: ["wie das Original", "kürzer", "ausführlicher"],
                        defaultValue: "wie das Original"
                    )
                ],
                temperature: 0.5
            ),

            AIPromptTool(
                id: "ai.summarize",
                title: "Zusammenfassen",
                subtitle: "Das Wesentliche aus langem Text",
                systemImage: "doc.text.magnifyingglass",
                categoryID: ToolCategory.everyday.id,
                keywords: ["zusammenfassung", "summary", "kürzen", "tldr"],
                instructions: """
                Du fasst Texte zusammen.

                \(baseRules)

                Vorgaben:
                - Form: {{option:format}}.
                - Wichtigstes zuerst. Keine Wertung, keine Ergänzungen.
                """,
                options: [
                    AIPromptOption(
                        id: "format",
                        label: "Form",
                        choices: ["drei Sätze", "Stichpunkte", "ein Absatz", "eine Zeile"],
                        defaultValue: "Stichpunkte"
                    )
                ],
                temperature: 0.3
            ),

            AIPromptTool(
                id: "ai.translate",
                title: "Übersetzen",
                subtitle: "Natürlich, nicht wörtlich",
                systemImage: "character.book.closed",
                categoryID: ToolCategory.everyday.id,
                keywords: ["übersetzen", "translate", "sprache", "englisch"],
                instructions: """
                Du übersetzt Texte nach {{option:target}}.

                Antworte ausschließlich mit der Übersetzung. Keine Einleitung, kein Kommentar.

                Regeln:
                - Übersetze sinngemäß, nicht Wort für Wort.
                - Fachbegriffe, Eigennamen und Code bleiben unverändert.
                - Register: {{option:register}}.
                """,
                options: [
                    AIPromptOption(
                        id: "target",
                        label: "Zielsprache",
                        choices: ["Englisch", "Deutsch", "Französisch", "Spanisch", "Italienisch"],
                        defaultValue: "Englisch"
                    ),
                    AIPromptOption(
                        id: "register",
                        label: "Register",
                        choices: ["neutral", "förmlich (Sie)", "locker (du)"],
                        defaultValue: "neutral"
                    )
                ],
                temperature: 0.3
            ),

            AIPromptTool(
                id: "ai.email",
                title: "E-Mail",
                subtitle: "Aus Stichworten eine Nachricht",
                systemImage: "envelope",
                categoryID: ToolCategory.everyday.id,
                keywords: ["email", "mail", "nachricht", "antwort", "schreiben"],
                instructions: """
                Du schreibst E-Mails aus Stichworten.

                \(baseRules)

                Format:
                - Erste Zeile "Betreff: …", dann eine Leerzeile.
                - Anrede, Hauptteil, Gruß.
                - Ton: {{option:tone}}. Länge: so kurz wie möglich.
                - Keine Floskeln wie "Ich hoffe, es geht Ihnen gut".
                """,
                options: [
                    AIPromptOption(
                        id: "tone",
                        label: "Ton",
                        choices: ["förmlich (Sie)", "kollegial (du)", "freundlich-knapp"],
                        defaultValue: "kollegial (du)"
                    )
                ],
                temperature: 0.5,
                inputPlaceholder: "Stichworte, worum es geht …"
            ),

            AIPromptTool(
                id: "ai.ideas",
                title: "Ideen sammeln",
                subtitle: "Varianten zu einer Frage",
                systemImage: "lightbulb",
                categoryID: ToolCategory.everyday.id,
                keywords: ["ideen", "brainstorming", "vorschläge", "namen"],
                instructions: """
                Du sammelst Ideen zu einer Frage.

                \(baseRules)

                Regeln:
                - {{option:count}} Vorschläge, einer pro Zeile, beginnend mit "- ".
                - Jeder Vorschlag höchstens eine Zeile, mit dem Unterschied zum vorigen im Kern.
                - Keine Varianten desselben Gedankens.
                """,
                options: [
                    AIPromptOption(
                        id: "count",
                        label: "Anzahl",
                        choices: ["5", "10", "20"],
                        defaultValue: "10"
                    )
                ],
                temperature: 0.9
            )
        ]
    }
}
