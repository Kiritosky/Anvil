import AnvilKit
import Foundation

/// Was Anvil von GitHub holt.
///
/// Zwei Dinge, mehr nicht: die Liste der eigenen Repositories und einen
/// flachen Klon zum Zählen. Alles andere kann der Browser besser.
public struct GitHubClient: Sendable {
    private let account: GitHubAccount
    private let runner = ProcessRunner()
    private let session: URLSession

    public init(account: GitHubAccount = GitHubAccount(), session: URLSession = .shared) {
        self.account = account
        self.session = session
    }

    // MARK: - Fragen

    /// Die Repositories des angemeldeten Kontos, das zuletzt bespielte zuerst.
    ///
    /// Ohne Token gibt es hier nichts zu holen: Die Liste der eigenen
    /// Repositories ist genau die Auskunft, für die man angemeldet sein muss.
    public func repositories(limit: Int = 100) async throws -> [GitHubRepository] {
        guard let token = account.token else {
            throw AnvilError.invalidInput(
                localized("Ohne Zugang gibt es keine Liste — verbinde Anvil in den Einstellungen mit GitHub.")
            )
        }

        var components = URLComponents(string: "https://api.github.com/user/repos")
        components?.queryItems = [
            URLQueryItem(name: "per_page", value: "\(min(max(limit, 1), 100))"),
            URLQueryItem(name: "sort", value: "pushed"),
            URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member")
        ]
        guard let url = components?.url else {
            throw AnvilError.unexpected(localized("Die Adresse ließ sich nicht bilden."))
        }

        return try await GitHubRepository.list(try await get(url, token: token))
    }

    /// Ein einzelnes Repository — auch eines, das dem Konto nicht gehört.
    public func repository(_ fullName: String) async throws -> GitHubRepository {
        guard let url = URL(string: "https://api.github.com/repos/\(fullName)") else {
            throw AnvilError.invalidInput(localized("„\(fullName)\" ist kein Repository-Name."))
        }

        let data = try await get(url, token: account.token)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let repository = GitHubRepository.read(object)
        else {
            throw AnvilError.invalidInput(localized("GitHub kennt „\(fullName)\" nicht."))
        }
        return repository
    }

    private func get(_ url: URL, token: String?) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw AnvilError.invalidInput(
                localized("GitHub hat den Zugang abgelehnt. Stimmt das Token noch?")
            )
        case 404:
            throw AnvilError.invalidInput(
                localized("GitHub kennt das nicht — oder das Token darf es nicht sehen.")
            )
        default:
            let statusCode = http.statusCode
            throw AnvilError.unexpected(localized("GitHub hat mit \(statusCode) geantwortet."))
        }
    }

    // MARK: - Holen

    /// Wie viel Geschichte geklont wird.
    ///
    /// Genau ein Commit: Gezählt wird der Stand von jetzt, und die
    /// Geschichte eines großen Repositories ist ein Vielfaches davon.
    public static let cloneDepth = 1

    /// Klont ein Repository flach in einen Ordner und gibt zurück, wo es
    /// liegt.
    ///
    /// - Parameter into: Wohin — normalerweise ein Ordner im temporären
    ///   Verzeichnis, den die Aufrufstelle danach wieder wegräumt.
    @discardableResult
    public func clone(_ repository: GitHubRepository, into folder: URL) async throws -> URL {
        let destination = folder.appending(path: ExportFile.sanitize(repository.name))
        let address = repository.cloneURL.isEmpty
            ? "https://github.com/\(repository.fullName).git"
            : repository.cloneURL

        let result = try await runner.run(
            "git",
            arguments: [
                "clone", "--depth", "\(Self.cloneDepth)", "--single-branch",
                "--no-tags", address, destination.path
            ],
            environment: account.token.map { GitHubAccount.environment(for: $0) },
            timeout: 600
        )

        guard result.succeeded else {
            // Was `git` beim Klonen sagt, steht auf der Fehlerausgabe — und
            // enthält bei einem privaten Repository ohne Zugang genau den
            // Hinweis, den man braucht.
            let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AnvilError.storage(
                localized("„\(repository.fullName)\" ließ sich nicht holen: \(detail)")
            )
        }

        return destination
    }
}
