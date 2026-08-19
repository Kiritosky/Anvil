import AnvilKit
import Foundation

/// Die Anmeldung bei GitHub, wie eine App ohne Server sie führen darf.
public struct GitHubDeviceLogin: Sendable {
    private let clientID: String
    private let session: URLSession

    /// - Parameter clientID: Leer heißt: die mitgelieferte. Wer das Feld in
    ///   den Einstellungen leert, will keine kaputte Anmeldung, sondern die
    ///   Voreinstellung zurück.
    public init(clientID: String = anvilClientID, session: URLSession = .shared) {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientID = trimmed.isEmpty ? Self.anvilClientID : trimmed
        self.session = session
    }

    /// Die OAuth-App, mit der Anvil selbst anfragt.
    public static let anvilClientID = "Ov23lihIKGGg0dCIJViw"

    /// Wofür Anvil um Erlaubnis bittet.
    public static let scope = "repo"

    /// Was der Mensch tun muss, damit die Anmeldung weitergeht.
    public struct Verification: Sendable, Hashable {
        /// Der Code zum Abtippen — GitHub schreibt ihn als `ABCD-1234`.
        public let userCode: String
        /// Die Seite, auf der er eingegeben wird.
        public let verificationURL: URL
        /// Womit Anvil nachfragt. Gehört nicht auf den Bildschirm.
        public let deviceCode: String
        /// Wie oft nachgefragt werden darf, in Sekunden.
        public let interval: TimeInterval
        /// Wie lange der Code gilt.
        public let expiresIn: TimeInterval

        public init(
            userCode: String,
            verificationURL: URL,
            deviceCode: String,
            interval: TimeInterval,
            expiresIn: TimeInterval
        ) {
            self.userCode = userCode
            self.verificationURL = verificationURL
            self.deviceCode = deviceCode
            self.interval = interval
            self.expiresIn = expiresIn
        }
    }

    /// Was beim Nachfragen herauskommt.
    public enum Answer: Sendable, Hashable {
        /// Fertig — hier ist das Token.
        case token(String)
        /// Der Mensch ist noch nicht fertig. Weiterfragen.
        case pending
        /// Zu schnell gefragt. Ab jetzt langsamer.
        case slowDown(TimeInterval)
    }

    // MARK: - Anfangen

    /// Holt einen Code und die Seite, auf der er eingegeben wird.
    public func start() async throws -> Verification {
        let data = try await post(
            "https://github.com/login/device/code",
            fields: ["client_id": clientID, "scope": Self.scope]
        )
        return try Self.readVerification(data)
    }

    /// Fragt einmal nach, ob der Mensch fertig ist.
    public func check(_ verification: Verification) async throws -> Answer {
        let data = try await post(
            "https://github.com/login/oauth/access_token",
            fields: [
                "client_id": clientID,
                "device_code": verification.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ]
        )
        return try Self.readAnswer(data)
    }

    private func post(_ address: String, fields: [String: String]) async throws -> Data {
        guard let url = URL(string: address) else {
            throw AnvilError.unexpected(localized("Die Adresse ließ sich nicht bilden."))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.form(fields).utf8)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let statusCode = http.statusCode
            throw AnvilError.unexpected(localized("GitHub hat mit \(statusCode) geantwortet."))
        }
        return data
    }

    /// Die Felder als Formular — in fester Reihenfolge, damit sich eine
    /// Anfrage vergleichen lässt.
    static func form(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")

        return fields.keys.sorted().map { key in
            let value = fields[key] ?? ""
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encoded)"
        }
        .joined(separator: "&")
    }

    // MARK: - Antworten lesen

    static func readVerification(_ data: Data) throws -> Verification {
        let object = try json(data)

        if let failure = error(in: object) { throw failure }

        guard let userCode = object["user_code"] as? String,
              let deviceCode = object["device_code"] as? String,
              let address = object["verification_uri"] as? String,
              let url = URL(string: address)
        else {
            throw AnvilError.unexpected(
                localized("GitHub hat die Anmeldung nicht angefangen.")
            )
        }

        return Verification(
            userCode: userCode,
            verificationURL: url,
            deviceCode: deviceCode,
            interval: number(object["interval"]) ?? 5,
            expiresIn: number(object["expires_in"]) ?? 900
        )
    }

    static func readAnswer(_ data: Data) throws -> Answer {
        let object = try json(data)

        if let token = object["access_token"] as? String, !token.isEmpty {
            return .token(token)
        }

        switch object["error"] as? String {
        case "authorization_pending":
            return .pending
        case "slow_down":
            return .slowDown(number(object["interval"]) ?? 10)
        default:
            if let failure = error(in: object) { throw failure }
            throw AnvilError.unexpected(localized("GitHub hat nichts Verwertbares geschickt."))
        }
    }

    /// Macht aus GitHubs Fehlerkennungen einen Satz, der weiterhilft.
    static func error(in object: [String: Any]) -> AnvilError? {
        guard let code = object["error"] as? String else { return nil }

        switch code {
        case "expired_token":
            return .invalidInput(
                localized("Der Code ist abgelaufen. Fang die Anmeldung noch einmal an.")
            )
        case "access_denied":
            return .invalidInput(localized("Die Anmeldung wurde bei GitHub abgelehnt."))
        case "unsupported_grant_type", "incorrect_client_credentials":
            return .invalidInput(
                localized("GitHub kennt diese Client-ID nicht — oder der Device Flow ist für sie nicht eingeschaltet.")
            )
        case "device_flow_disabled":
            return .invalidInput(
                localized("Für diese App ist der Device Flow bei GitHub nicht eingeschaltet.")
            )
        default:
            let description = object["error_description"] as? String ?? code
            return .unexpected(localized("GitHub sagt: \(description)"))
        }
    }

    private static func json(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnvilError.unexpected(localized("GitHub hat nichts Verwertbares geschickt."))
        }
        return object
    }

    /// GitHub schickt Zahlen mal als Zahl, mal als Zeichenkette.
    private static func number(_ value: Any?) -> TimeInterval? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return TimeInterval(number) }
        if let text = value as? String { return TimeInterval(text) }
        return nil
    }
}

extension SettingKey {
    /// Die Client-ID der eigenen OAuth-App bei GitHub.
    public static var githubClientID: SettingKey<String> {
        SettingKey<String>("github.clientID", default: GitHubDeviceLogin.anvilClientID)
    }
}
