import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Die Anmeldung bei GitHub")
struct GitHubDeviceLoginTests {
    // MARK: - Anfangen

    @Test
    func theCodeAndThePageAreRead() throws {
        let verification = try GitHubDeviceLogin.readVerification(Data("""
            {
              "device_code": "3584d83530557fdd1f46af8289938c8ef79f9dc5",
              "user_code": "WDJB-MJHT",
              "verification_uri": "https://github.com/login/device",
              "expires_in": 900,
              "interval": 5
            }
            """.utf8))

        #expect(verification.userCode == "WDJB-MJHT")
        #expect(verification.verificationURL.absoluteString == "https://github.com/login/device")
        #expect(verification.deviceCode == "3584d83530557fdd1f46af8289938c8ef79f9dc5")
        #expect(verification.interval == 5)
        #expect(verification.expiresIn == 900)
    }

    /// Ohne Angabe gilt, was in der Norm steht — fünf Sekunden sind höflich.
    @Test
    func aMissingIntervalHasADefault() throws {
        let verification = try GitHubDeviceLogin.readVerification(Data("""
            {"device_code":"abc","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device"}
            """.utf8))

        #expect(verification.interval == 5)
        #expect(verification.expiresIn == 900)
    }

    @Test
    func anAnswerWithoutACodeIsAFailure() {
        #expect(throws: AnvilError.self) {
            try GitHubDeviceLogin.readVerification(Data(#"{"error":"unauthorized_client"}"#.utf8))
        }
        #expect(throws: AnvilError.self) {
            try GitHubDeviceLogin.readVerification(Data(#"{}"#.utf8))
        }
    }

    // MARK: - Nachfragen

    @Test
    func theTokenIsRecognised() throws {
        let answer = try GitHubDeviceLogin.readAnswer(Data("""
            {"access_token":"gho_geheim","token_type":"bearer","scope":"repo"}
            """.utf8))
        #expect(answer == .token("gho_geheim"))
    }

    /// Der Normalfall beim ersten Nachfragen: Der Mensch tippt noch.
    @Test
    func waitingIsNoFailure() throws {
        let answer = try GitHubDeviceLogin.readAnswer(
            Data(#"{"error":"authorization_pending"}"#.utf8)
        )
        #expect(answer == .pending)
    }

    /// GitHub sagt dazu, wie lange — und meint es ernst.
    @Test
    func slowDownCarriesTheNewInterval() throws {
        let answer = try GitHubDeviceLogin.readAnswer(
            Data(#"{"error":"slow_down","interval":10}"#.utf8)
        )
        #expect(answer == .slowDown(10))
    }

    @Test
    func anExpiredCodeSaysSo() {
        #expect(throws: AnvilError.self) {
            try GitHubDeviceLogin.readAnswer(Data(#"{"error":"expired_token"}"#.utf8))
        }
    }

    @Test
    func aDeniedSignInSaysSo() {
        #expect(throws: AnvilError.self) {
            try GitHubDeviceLogin.readAnswer(Data(#"{"error":"access_denied"}"#.utf8))
        }
    }

    /// Der häufigste Einrichtungsfehler: Die OAuth-App gibt es, aber der
    /// Device Flow ist bei ihr nicht eingeschaltet.
    @Test
    func aSwitchedOffDeviceFlowIsExplained() throws {
        let failure = try #require(
            GitHubDeviceLogin.error(in: ["error": "device_flow_disabled"])
        )
        #expect(failure.message.contains("Device Flow"))
    }

    @Test
    func anUnknownFailureKeepsWhatGitHubSaid() throws {
        let failure = try #require(
            GitHubDeviceLogin.error(in: [
                "error": "something_else",
                "error_description": "Kaputt und zwar richtig"
            ])
        )
        #expect(failure.message.contains("Kaputt und zwar richtig"))
    }

    @Test
    func nothingWrongMeansNoFailure() {
        #expect(GitHubDeviceLogin.error(in: ["access_token": "gho_geheim"]) == nil)
    }

    // MARK: - Die Anfrage

    /// Ein Formular, das GitHub versteht: Was Sonderzeichen hat, wird
    /// verpackt — der Bindestrich im Kennungsnamen aber nicht.
    @Test
    func theFormIsEncoded() {
        let form = GitHubDeviceLogin.form([
            "client_id": "Iv1.abc",
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ])

        #expect(form.contains("client_id=Iv1.abc"))
        #expect(form.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"))
        #expect(form.components(separatedBy: "&").count == 2)
    }

    /// Feste Reihenfolge, damit sich zwei Anfragen vergleichen lassen.
    @Test
    func theFieldsComeInOrder() {
        let form = GitHubDeviceLogin.form(["b": "2", "a": "1", "c": "3"])
        #expect(form == "a=1&b=2&c=3")
    }

    /// Anvil fragt nach dem kleinsten Recht, das reicht — und nach keinem
    /// weiteren.
    @Test
    func onlyOneScopeIsAskedFor() {
        #expect(GitHubDeviceLogin.scope == "repo")
    }
}
