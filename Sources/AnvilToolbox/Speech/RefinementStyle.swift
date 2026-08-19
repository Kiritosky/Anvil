import AnvilKit
import Foundation

/// What the model should turn a raw transcript into.
public enum RefinementStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Keep every word; fix only the speaking noise, grammar and punctuation.
    case verbatim
    /// Readable prose: same content, proper sentences and paragraphs.
    case polished
    /// Shorter, without losing anything that matters.
    case concise
    /// Bullet points.
    case bullets
    /// A short summary.
    case summary
    /// What was decided and who does what.
    case actionItems
    /// A ready-to-send message.
    case email
    /// A conventional-commits message.
    case commitMessage
    /// A doc comment for the code that was described.
    case codeComment
    /// Whatever the user typed into the custom instruction field.
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .verbatim: localized("Wortgetreu säubern")
        case .polished: localized("Sauberer Text")
        case .concise: localized("Gekürzt")
        case .bullets: localized("Stichpunkte")
        case .summary: localized("Zusammenfassung")
        case .actionItems: localized("To-dos")
        case .email: localized("E-Mail")
        case .commitMessage: localized("Commit-Message")
        case .codeComment: localized("Code-Kommentar")
        case .custom: localized("Eigene Anweisung")
        }
    }

    public var systemImage: String {
        switch self {
        case .verbatim: "eraser"
        case .polished: "text.alignleft"
        case .concise: "arrow.down.right.and.arrow.up.left"
        case .bullets: "list.bullet"
        case .summary: "doc.text"
        case .actionItems: "checklist"
        case .email: "envelope"
        case .commitMessage: "arrow.triangle.branch"
        case .codeComment: "chevron.left.forwardslash.chevron.right"
        case .custom: "wand.and.stars"
        }
    }

    public var explanation: String {
        switch self {
        case .verbatim:
            localized("Behält jedes inhaltliche Wort. Nur Verzögerungslaute, Versprecher, Grammatik und Zeichensetzung werden korrigiert.")
        case .polished:
            localized("Schreibt das Diktat in flüssige Sätze und Absätze um, ohne Inhalt zu ergänzen.")
        case .concise:
            localized("Kürzt auf das Wesentliche, behält aber alle Aussagen.")
        case .bullets:
            localized("Gliedert den Inhalt in Stichpunkte.")
        case .summary:
            localized("Fasst das Gesagte in wenigen Sätzen zusammen.")
        case .actionItems:
            localized("Zieht Aufgaben, Zuständigkeiten und Entscheidungen heraus.")
        case .email:
            localized("Formuliert eine versandfertige Nachricht mit Anrede und Schluss.")
        case .commitMessage:
            localized("Formt eine Commit-Message nach Conventional Commits.")
        case .codeComment:
            localized("Macht aus der Beschreibung einen Doku-Kommentar.")
        case .custom:
            localized("Deine eigene Anweisung an das Modell.")
        }
    }

    /// Whether the result should still be the speaker's own wording.
    public var preservesWording: Bool {
        self == .verbatim
    }

    /// Low temperature for cleanup, higher where phrasing is being invented.
    public var temperature: Double {
        switch self {
        case .verbatim: 0.05
        case .polished, .concise, .bullets, .commitMessage, .codeComment: 0.2
        case .summary, .actionItems: 0.3
        case .email: 0.4
        case .custom: 0.3
        }
    }

    /// The styles offered as chips, in the order they appear.
    public static var offered: [RefinementStyle] {
        [.verbatim, .polished, .concise, .bullets, .summary, .actionItems, .email, .commitMessage, .codeComment, .custom]
    }

    // MARK: - Prompting

    /// The standing instruction sent as the model's role.
    public func instructions(
        languageName: String,
        customInstruction: String = "",
        vocabulary: [String] = []
    ) -> String {
        let shared = """
        Du bearbeitest Text, der per Spracherkennung aus einem Diktat entstanden ist.

        Feste Regeln:
        - Antworte ausschließlich mit dem bearbeiteten Text. Keine Einleitung, \
        keine Erklärung, keine Anführungszeichen um das Ergebnis, keine Markdown-Codeblöcke.
        - Schreibe in \(languageName). Übersetze niemals in eine andere Sprache.
        - Erfinde keine Inhalte. Was nicht gesagt wurde, steht auch nicht im Ergebnis.
        - Erkennungsfehler bei Fachbegriffen, Namen und Code-Bezeichnern korrigierst du \
        anhand des Zusammenhangs, wenn die richtige Form eindeutig ist.
        """

        let specific = switch self {
        case .verbatim:
            """
            Aufgabe: Säubere das Diktat, ohne es umzuschreiben.
            - Entferne Verzögerungslaute, Wortwiederholungen und abgebrochene Ansätze.
            - Korrigiere Grammatik, Groß- und Kleinschreibung und Zeichensetzung.
            - Setze Absätze, wo das Thema wechselt.
            - Behalte Wortwahl, Reihenfolge und Ton der sprechenden Person bei. \
            Formuliere keinen Satz um, der auch so verständlich ist.
            """
        case .polished:
            """
            Aufgabe: Mach daraus sauberen Fließtext.
            - Vollständige, gut lesbare Sätze und sinnvolle Absätze.
            - Gesprochene Satzstellung darfst du glätten, der Inhalt bleibt vollständig.
            - Kein Amtsdeutsch, keine Floskeln.
            """
        case .concise:
            """
            Aufgabe: Kürze den Text deutlich.
            - Jede Aussage bleibt erhalten, Wiederholungen und Ausschmückungen fallen weg.
            - Ziel sind etwa halb so viele Wörter.
            """
        case .bullets:
            """
            Aufgabe: Gliedere den Inhalt in Stichpunkte.
            - Ein Gedanke pro Punkt, beginnend mit "- ".
            - Untergeordnete Punkte eingerückt, höchstens zwei Ebenen.
            - Keine Einleitung und kein Fazit.
            """
        case .summary:
            """
            Aufgabe: Fasse zusammen.
            - Drei bis fünf Sätze, die Wichtigstes zuerst nennen.
            """
        case .actionItems:
            """
            Aufgabe: Zieh die Aufgaben heraus.
            - Eine Zeile pro Aufgabe, beginnend mit "- [ ] ".
            - Nenne die zuständige Person und die Frist, sofern sie gesagt wurden.
            - Wenn keine Aufgaben genannt wurden, antworte mit "Keine Aufgaben genannt."
            """
        case .email:
            """
            Aufgabe: Formuliere eine versandfertige E-Mail.
            - Erste Zeile "Betreff: …", danach eine Leerzeile.
            - Passende Anrede, klarer Hauptteil, kurzer Gruß.
            - Ton: freundlich und sachlich.
            """
        case .commitMessage:
            """
            Aufgabe: Schreibe eine Commit-Message nach Conventional Commits.
            - Erste Zeile: "typ(bereich): beschreibung", höchstens 72 Zeichen, Imperativ, kein Punkt am Ende.
            - Wenn es mehr zu sagen gibt: Leerzeile, dann Fließtext, der das Warum erklärt.
            - Erlaubte Typen: feat, fix, refactor, docs, test, chore, perf, build, ci.
            """
        case .codeComment:
            """
            Aufgabe: Mach daraus einen Doku-Kommentar.
            - Erster Satz beschreibt in einer Zeile, was der Code tut.
            - Danach nur, was nicht schon im Code steht: Warum, Randfälle, Annahmen.
            - Reiner Text ohne Kommentarzeichen — die setzt der Editor.
            """
        case .custom:
            customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Aufgabe: Säubere das Diktat und korrigiere Grammatik und Zeichensetzung."
                : "Aufgabe: \(customInstruction)"
        }

        return [shared, Self.vocabularySection(vocabulary), specific]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// The word list, as a rule rather than as a suggestion.
    private static func vocabularySection(_ terms: [String]) -> String {
        let cleaned = terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }

        return """
        Eigene Schreibweisen (Produkte, Namen, Fachbegriffe). Diese Begriffe stehen \
        bereits richtig im Text und bleiben Zeichen für Zeichen so stehen — auch wenn \
        du sie nicht kennst. Beuge sie grammatisch, aber schreibe sie niemals um:
        \(cleaned.map { "- \($0)" }.joined(separator: "\n"))
        """
    }
}
