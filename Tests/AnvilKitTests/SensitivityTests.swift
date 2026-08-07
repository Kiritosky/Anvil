import Foundation
import Testing

@testable import AnvilKit

@Suite("Sensitivity")
struct SensitivityTests {
    // MARK: - Was gemerkt werden darf

    /// Der Normalfall. Wäre das hier vertraulich, wäre das ganze Merken
    /// wertlos — dann bliebe nie etwas übrig.
    @Test
    func ordinaryTextIsNotConfidential() {
        #expect(!Sensitivity.looksConfidential("Hallo Welt"))
        #expect(!Sensitivity.looksConfidential("{ \"name\": \"Anvil\", \"version\": 2 }"))
        #expect(!Sensitivity.looksConfidential("https://anvil.dev/docs?seite=3"))
        #expect(!Sensitivity.looksConfidential(""))
    }

    /// Über Geheimnisse zu schreiben ist kein Geheimnis. „Passwort vergessen?"
    /// gehört in jede zweite Übersetzung und darf das Merken nicht abschalten.
    @Test
    func talkingAboutSecretsIsNotASecret() {
        #expect(!Sensitivity.looksConfidential("Passwort vergessen?"))
        #expect(!Sensitivity.looksConfidential("Bitte das Passwort zurücksetzen."))
        #expect(!Sensitivity.looksConfidential("password:"))
    }

    // MARK: - Was nicht gespeichert werden darf

    @Test
    func recognisesKeyFiles() {
        #expect(Sensitivity.looksConfidential("-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n"))
        #expect(Sensitivity.looksConfidential("-----BEGIN CERTIFICATE-----"))
        #expect(Sensitivity.looksConfidential("ssh-ed25519 AAAAC3NzaC1lZDI1 kiri@mac"))
    }

    /// Die Anbieter, die ihren Schlüsseln ein Präfix geben, machen es leicht.
    @Test
    func recognisesProviderTokens() {
        #expect(Sensitivity.looksConfidential("sk-abcdefghijklmnopqrstuvwxyz012345"))
        #expect(Sensitivity.looksConfidential("ghp_1234567890abcdefghijklmnopqrstuvwxyz"))
        #expect(Sensitivity.looksConfidential("AKIAIOSFODNN7EXAMPLE"))
        #expect(Sensitivity.looksConfidential("Nimm glpat-xxxxxxxxxxxxxxxxxxxx dafür"))
    }

    /// Ein kurzes Wort mit demselben Anfang ist keiner. „sk-" steht auch am
    /// Anfang von Abkürzungen.
    @Test
    func aShortWordWithTheSamePrefixIsNotAToken() {
        #expect(!Sensitivity.looksConfidential("sk-1"))
        #expect(!Sensitivity.looksConfidential("hf_x"))
    }

    @Test
    func recognisesJSONWebTokens() {
        let token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r"
        #expect(Sensitivity.looksConfidential(token))
        #expect(Sensitivity.looksConfidential("Header: Bearer \(token)"))
    }

    /// Zwei Teile sind kein JWT — und irgendein Wort, das mit „eyJ" beginnt,
    /// erst recht nicht.
    @Test
    func doesNotSeeATokenInEveryBase64String() {
        #expect(!Sensitivity.looksConfidential("eyJhbGciOiJIUzI1NiJ9"))
        #expect(!Sensitivity.looksConfidential("eyJ"))
    }

    /// Konfigurationszeilen: erst das Wort, dann ein Trennzeichen, dann ein
    /// Wert mit Substanz.
    @Test
    func recognisesConfigurationLines() {
        #expect(Sensitivity.looksConfidential("API_KEY=abc123def456"))
        #expect(Sensitivity.looksConfidential("client_secret: s3cr3t-value"))
        #expect(Sensitivity.looksConfidential("Authorization: Bearer abc123def"))
        #expect(Sensitivity.looksConfidential("{\n  \"access_token\": \"abcdef123456\"\n}"))
    }

    /// Ein Wert ohne Substanz ist eine Vorlage, kein Geheimnis.
    @Test
    func aPlaceholderIsNotASecret() {
        #expect(!Sensitivity.looksConfidential("API_KEY="))
        #expect(!Sensitivity.looksConfidential("password: x"))
    }
}

@Suite("DraftStore")
@MainActor
struct DraftStoreTests {
    private func makeStore() -> (DraftStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "anvil-drafts-\(UUID().uuidString)")
        return (DraftStore(directory: directory), directory)
    }

    @Test
    func remembersAndReturnsADraft() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.save(DraftStore.Draft(input: "Hallo", modeID: "pretty"), for: "text.json")

        let draft = store.draft(for: "text.json")
        #expect(draft?.input == "Hallo")
        #expect(draft?.modeID == "pretty")
    }

    /// Der eigentliche Punkt: was nach einem Geheimnis aussieht, landet nicht
    /// auf der Platte — auch wenn das Werkzeug selbst harmlos ist.
    @Test
    func neverStoresSomethingConfidential() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.save(DraftStore.Draft(input: "sk-abcdefghijklmnopqrstuvwxyz012345"), for: "text.json")
        #expect(store.draft(for: "text.json") == nil)
    }

    /// Und der Fall, den man leicht übersieht: erst etwas Harmloses, dann ein
    /// Schlüssel. Bliebe das Harmlose stehen, hätte man auf der Platte einen
    /// Stand, den es im Fenster nie gab.
    @Test
    func aSecretRemovesWhatWasStoredBefore() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.save(DraftStore.Draft(input: "Harmlos"), for: "text.json")
        #expect(store.draft(for: "text.json") != nil)

        store.save(DraftStore.Draft(input: "API_KEY=abc123def456"), for: "text.json")
        #expect(store.draft(for: "text.json") == nil)
    }

    /// Dasselbe, wenn das Werkzeug selbst gesperrt ist — dort wird gar nicht
    /// erst geprüft, wie harmlos der Text aussieht.
    @Test
    func aForbiddenToolStoresNothing() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.save(DraftStore.Draft(input: "Harmlos"), for: "text.jwt", allowed: false)
        #expect(store.draft(for: "text.jwt") == nil)
    }

    @Test
    func doesNotStoreEmptyOrOversizedInput() {
        #expect(!DraftStore.mayStore(""))
        #expect(!DraftStore.mayStore("   \n  "))
        #expect(!DraftStore.mayStore(String(repeating: "a", count: DraftStore.sizeLimit + 1)))
        #expect(DraftStore.mayStore("etwas Kurzes"))
    }

    @Test
    func forgettingEverythingLeavesNothingBehind() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.save(DraftStore.Draft(input: "eins"), for: "text.json")
        store.save(DraftStore.Draft(input: "zwei"), for: "text.slug")
        store.forgetEverything()

        #expect(store.draft(for: "text.json") == nil)
        #expect(store.draft(for: "text.slug") == nil)
    }

    /// Ein Neustart der App ist ein neuer Store auf demselben Verzeichnis —
    /// ohne diesen Weg wäre das ganze Merken nur ein Zwischenspeicher.
    @Test
    func survivesANewStoreOnTheSameDirectory() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.save(DraftStore.Draft(input: "bleibt"), for: "text.case")

        let reopened = DraftStore(directory: directory)
        #expect(reopened.draft(for: "text.case")?.input == "bleibt")
    }
}
