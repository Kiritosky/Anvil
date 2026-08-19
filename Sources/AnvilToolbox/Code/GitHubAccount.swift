import AnvilKit
import Foundation

/// Die Verbindung zu GitHub.
public struct GitHubAccount: Sendable {
    private let keychain: KeychainStore

    /// Unter diesem Namen liegt das Token im Schlüsselbund.
    public static let keychainAccount = "github.token"

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    public var token: String? {
        keychain.secret(for: Self.keychainAccount)
    }

    public var isConnected: Bool { token?.isEmpty == false }

    /// Legt das Token ab — oder wirft es weg.
    public func connect(_ token: String?) throws {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        try keychain.setSecret(trimmed?.isEmpty == true ? nil : trimmed, for: Self.keychainAccount)
    }

    /// Die Umgebung, mit der `git` das Token benutzt, ohne es preiszugeben.
    public static func environment(for token: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let value = "Basic " + Data("x-access-token:\(token)".utf8).base64EncodedString()

        environment["GIT_CONFIG_COUNT"] = "1"
        environment["GIT_CONFIG_KEY_0"] = "http.https://github.com/.extraheader"
        environment["GIT_CONFIG_VALUE_0"] = "Authorization: \(value)"

        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_ASKPASS"] = "/usr/bin/true"
        environment["SSH_ASKPASS"] = "/usr/bin/true"
        return environment
    }

    /// Was in der Oberfläche über den Zugang steht.
    public var status: String {
        isConnected
            ? localized("Verbunden — private Repositories gehen auch.")
            : localized("Nicht verbunden — nur öffentliche Repositories.")
    }
}

/// Ein Repository, wie GitHub es beschreibt.
public struct GitHubRepository: Sendable, Hashable, Identifiable {
    /// `anvil` — der Name ohne Besitzer.
    public let name: String
    /// `kiritosky/anvil` — so, wie man es hinschreibt.
    public let fullName: String
    public let isPrivate: Bool
    public let description: String
    /// Die Sprache, für die GitHub das Repository hält.
    public let language: String
    public let cloneURL: String
    /// Wann dort zuletzt etwas passiert ist, als Text von GitHub.
    public let pushedAt: String

    public var id: String { fullName }

    public var owner: String {
        fullName.components(separatedBy: "/").first ?? ""
    }

    public init(
        name: String,
        fullName: String,
        isPrivate: Bool = false,
        description: String = "",
        language: String = "",
        cloneURL: String = "",
        pushedAt: String = ""
    ) {
        self.name = name
        self.fullName = fullName
        self.isPrivate = isPrivate
        self.description = description
        self.language = language
        self.cloneURL = cloneURL
        self.pushedAt = pushedAt
    }

    // MARK: - Lesen

    /// Liest die Antwort von `GET /user/repos`.
    public static func list(_ json: Data) throws -> [GitHubRepository] {
        guard let array = try JSONSerialization.jsonObject(with: json) as? [[String: Any]] else {
            throw AnvilError.invalidInput(localized("GitHub hat keine Liste geschickt."))
        }
        return array.compactMap { read($0) }
    }

    static func read(_ object: [String: Any]) -> GitHubRepository? {
        guard let fullName = object["full_name"] as? String else { return nil }
        return GitHubRepository(
            name: object["name"] as? String ?? fullName,
            fullName: fullName,
            isPrivate: object["private"] as? Bool ?? false,
            description: object["description"] as? String ?? "",
            language: object["language"] as? String ?? "",
            cloneURL: object["clone_url"] as? String ?? "https://github.com/\(fullName).git",
            pushedAt: object["pushed_at"] as? String ?? ""
        )
    }

    /// Was jemand in ein Feld tippt, als `owner/repo`.
    public static func fullName(from text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        for prefix in ["https://github.com/", "http://github.com/", "git@github.com:"] {
            if value.hasPrefix(prefix) { value = String(value.dropFirst(prefix.count)) }
        }
        if value.hasSuffix(".git") { value = String(value.dropLast(4)) }

        let parts = value.components(separatedBy: "/").filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        return "\(parts[0])/\(parts[1])"
    }
}
