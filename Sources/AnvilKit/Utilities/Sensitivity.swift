import Foundation

/// Die Frage, ob ein Text auf der Platte liegen darf.
///
/// Anvil merkt sich, was in einem Werkzeug stand — aber nur, wenn es nicht
/// nach etwas aussieht, das niemand wiederfinden soll. Ein Schlüssel, den man
/// einmal kurz eingefügt hat, hat in einer Datei nichts verloren, die
/// unverschlüsselt neben den Einstellungen liegt.
///
/// Die Prüfung ist absichtlich in die falsche Richtung ungenau: sie hält
/// lieber etwas Harmloses für geheim als umgekehrt. Ein Fehlalarm kostet, dass
/// man nach dem Neustart neu einfügen muss. Ein übersehener Schlüssel kostet
/// den Schlüssel.
public enum Sensitivity {
    /// Sieht der Text nach etwas aus, das nicht gespeichert werden darf?
    public static func looksConfidential(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if containsKeyBlock(trimmed) { return true }
        if containsWiFiCredentials(trimmed) { return true }
        if containsKnownTokenPrefix(trimmed) { return true }
        if containsJSONWebToken(trimmed) { return true }
        if namesASecret(trimmed) { return true }
        return false
    }

    // MARK: - Die einzelnen Anzeichen

    /// Schlüsseldateien und Zertifikate sagen selbst, was sie sind.
    private static func containsKeyBlock(_ text: String) -> Bool {
        let markers = [
            "-----BEGIN", "PRIVATE KEY", "ssh-rsa ", "ssh-ed25519 ", "PuTTY-User-Key"
        ]
        return markers.contains { text.localizedCaseInsensitiveContains($0) }
    }

    /// Der QR-Code, mit dem man Gäste ins WLAN lässt, trägt das Passwort im
    /// Klartext: `WIFI:T:WPA;S:Netz;P:geheim;;`. Das Wort „password" kommt
    /// darin nicht vor — ohne diesen Fall würde ausgerechnet der häufigste
    /// selbstgebaute QR-Code gemerkt.
    private static func containsWiFiCredentials(_ text: String) -> Bool {
        let upper = text.uppercased()
        return upper.contains("WIFI:") && upper.contains("P:")
    }

    /// Die Anbieter, die ihren Schlüsseln ein erkennbares Präfix geben. Wer
    /// eines davon findet, muss nicht mehr raten.
    private static func containsKnownTokenPrefix(_ text: String) -> Bool {
        // Groß-/Kleinschreibung zählt hier: „AKIA" ist ein AWS-Schlüssel,
        // „akia" ist ein Wort in irgendeiner Sprache.
        let prefixes = [
            "sk-", "sk_live_", "pk_live_", "rk_live_",
            "ghp_", "gho_", "ghu_", "ghs_", "github_pat_",
            "glpat-", "xoxb-", "xoxp-", "xapp-",
            "AKIA", "ASIA", "AIza", "ya29.",
            "hf_", "npm_", "dop_v1_", "SG."
        ]
        return text.split(whereSeparator: \.isWhitespace).contains { word in
            prefixes.contains { word.hasPrefix($0) && word.count > $0.count + 8 }
        }
    }

    /// Ein JWT trägt seinen Kopf im Klartext: `{"alg"` in Base64 beginnt immer
    /// mit `eyJ`. Drei durch Punkte getrennte Teile machen es eindeutig.
    private static func containsJSONWebToken(_ text: String) -> Bool {
        text.split(whereSeparator: \.isWhitespace).contains { word in
            guard word.hasPrefix("eyJ") else { return false }
            let parts = word.split(separator: ".", omittingEmptySubsequences: false)
            return parts.count == 3 && parts.allSatisfy { $0.count >= 8 }
        }
    }

    /// Konfigurationszeilen, die ihr Geheimnis benennen: `API_KEY=…`,
    /// `password: …`, `Authorization: Bearer …`.
    ///
    /// Das bloße Wort reicht nicht — „Passwort vergessen?" in einem
    /// übersetzten Text ist kein Geheimnis. Erst ein Wert dahinter macht es
    /// zu einem.
    private static func namesASecret(_ text: String) -> Bool {
        let words = [
            "password", "passwort", "passwd", "secret", "geheim",
            "api_key", "apikey", "api-key", "access_token", "refresh_token",
            "client_secret", "private_key", "authorization"
        ]

        for line in text.components(separatedBy: .newlines) {
            let lowered = line.lowercased()
            guard let word = words.first(where: { lowered.contains($0) }) else { continue }
            guard let range = lowered.range(of: word) else { continue }

            // Was hinter dem Wort steht: erst ein Trennzeichen, dann etwas mit
            // Substanz. „password:" allein ist eine Überschrift.
            let rest = lowered[range.upperBound...]
                .drop { $0 == "\"" || $0 == "'" || $0 == " " }
            guard let separator = rest.first, separator == "=" || separator == ":" else { continue }

            let value = rest.dropFirst()
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            if value.count >= 6 { return true }
        }
        return false
    }
}
