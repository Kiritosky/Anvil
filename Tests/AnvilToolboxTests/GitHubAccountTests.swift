import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("GitHub-Repositories lesen")
struct GitHubRepositoryTests {
    private let sample = """
        [
          {
            "name": "anvil",
            "full_name": "kiritosky/anvil",
            "private": true,
            "description": "Werkzeugkasten",
            "language": "Swift",
            "clone_url": "https://github.com/kiritosky/anvil.git",
            "pushed_at": "2026-08-16T05:00:00Z"
          },
          {
            "name": "nook",
            "full_name": "kiritosky/nook",
            "private": false
          }
        ]
        """

    @Test
    func everyFieldThatMattersIsRead() throws {
        let list = try GitHubRepository.list(Data(sample.utf8))
        let first = try #require(list.first)

        #expect(list.count == 2)
        #expect(first.name == "anvil")
        #expect(first.fullName == "kiritosky/anvil")
        #expect(first.isPrivate)
        #expect(first.language == "Swift")
        #expect(first.owner == "kiritosky")
    }

    /// Fehlende Felder sind kein Fehler: GitHub lässt `description` und
    /// `language` weg, wenn nichts drinsteht.
    @Test
    func missingFieldsAreNoFailure() throws {
        let list = try GitHubRepository.list(Data(sample.utf8))
        let second = try #require(list.last)

        #expect(second.description.isEmpty)
        #expect(second.language.isEmpty)
        #expect(second.cloneURL == "https://github.com/kiritosky/nook.git")
    }

    @Test
    func somethingElseThanAListThrows() {
        #expect(throws: AnvilError.self) {
            try GitHubRepository.list(Data(#"{"message":"Bad credentials"}"#.utf8))
        }
    }

    /// Wer ein Repository sucht, hat meistens die Adresse im
    /// Zwischenspeicher und nicht den Namen im Kopf.
    @Test
    func aPastedAddressBecomesAName() {
        #expect(GitHubRepository.fullName(from: "kiritosky/anvil") == "kiritosky/anvil")
        #expect(
            GitHubRepository.fullName(from: "https://github.com/kiritosky/anvil")
                == "kiritosky/anvil"
        )
        #expect(
            GitHubRepository.fullName(from: "https://github.com/kiritosky/anvil.git")
                == "kiritosky/anvil"
        )
        #expect(
            GitHubRepository.fullName(from: "git@github.com:kiritosky/anvil.git")
                == "kiritosky/anvil"
        )
    }

    /// Eine Adresse mit mehr dahinter — ein Zweig, eine Datei — meint immer
    /// noch dasselbe Repository.
    @Test
    func whatComesAfterTheNameIsIgnored() {
        #expect(
            GitHubRepository.fullName(from: "https://github.com/kiritosky/anvil/tree/main")
                == "kiritosky/anvil"
        )
    }

    @Test
    func whatIsNoNameIsRejected() {
        #expect(GitHubRepository.fullName(from: "") == nil)
        #expect(GitHubRepository.fullName(from: "anvil") == nil)
        #expect(GitHubRepository.fullName(from: "   ") == nil)
    }
}

@Suite("Der Zugang zu GitHub")
struct GitHubAccountTests {
    /// Das Token darf nicht als Argument an `git` gehen: Argumente stehen für
    /// jeden in der Prozessliste. Über die Umgebung geht es nur an `git`
    /// selbst — und auch dort nur für diesen einen Aufruf.
    @Test
    func theTokenTravelsThroughTheEnvironment() throws {
        let environment = GitHubAccount.environment(for: "ghp_geheim")

        #expect(environment["GIT_CONFIG_COUNT"] == "1")
        #expect(environment["GIT_CONFIG_KEY_0"] == "http.https://github.com/.extraheader")

        let value = try #require(environment["GIT_CONFIG_VALUE_0"])
        #expect(value.hasPrefix("Authorization: Basic "))

        let encoded = value.replacingOccurrences(of: "Authorization: Basic ", with: "")
        let decoded = try #require(Data(base64Encoded: encoded))
        #expect(String(decoding: decoded, as: UTF8.self) == "x-access-token:ghp_geheim")
    }

    /// Ohne das wartet `git` bei einem falschen Token auf eine Eingabe, die
    /// niemand machen kann — die App hat kein Terminal.
    @Test
    func nothingWaitsForAPassword() {
        let environment = GitHubAccount.environment(for: "ghp_geheim")
        #expect(environment["GIT_TERMINAL_PROMPT"] == "0")
        #expect(environment["GIT_ASKPASS"] == "/usr/bin/true")
    }

    /// Der Schlüsselbund im Test ist derselbe wie in der App — deshalb ein
    /// eigener Dienstname, damit ein Testlauf keinen echten Zugang wegwirft.
    @Test
    func aTokenCanBeStoredAndTakenBack() throws {
        let service = "dev.anvil.tests.github.\(UUID().uuidString)"
        let account = GitHubAccount(keychain: KeychainStore(service: service))

        #expect(!account.isConnected)
        try account.connect("ghp_geheim")
        #expect(account.isConnected)
        #expect(account.token == "ghp_geheim")

        try account.connect(nil)
        #expect(!account.isConnected)
    }

    /// Leerzeichen um ein eingefügtes Token herum sind kein Token.
    @Test
    func whitespaceAroundATokenIsTrimmed() throws {
        let service = "dev.anvil.tests.github.\(UUID().uuidString)"
        let account = GitHubAccount(keychain: KeychainStore(service: service))

        try account.connect("  ghp_geheim\n")
        #expect(account.token == "ghp_geheim")

        try account.connect("   ")
        #expect(!account.isConnected)
    }
}
