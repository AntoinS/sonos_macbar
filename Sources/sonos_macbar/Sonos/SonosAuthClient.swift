import Foundation

actor SonosAuthClient {
    private let configuration: SonosAuthConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()
    private var throttle = SonosRequestThrottle()

    init(configuration: SonosAuthConfiguration = .production, session: URLSession? = nil) {
        self.configuration = configuration

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 15
        sessionConfiguration.timeoutIntervalForResource = 15
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = session ?? URLSession(
            configuration: sessionConfiguration,
            delegate: NoRedirectURLSessionDelegate(),
            delegateQueue: nil
        )
    }

    func health() async throws -> SonosAuthHealthResponse {
        try await request(.get, path: "health", body: Optional<EmptyAuthRequest>.none)
    }

    func startOAuth() async throws -> SonosOAuthStartResponse {
        let response: SonosOAuthStartResponse = try await request(
            .post,
            path: "oauth/start",
            body: EmptyAuthRequest()
        )

        guard response.loginId.isEmpty == false,
              response.expiresIn > 0,
              response.expiresIn <= 600,
              response.authorizationURL.scheme == "https",
              response.authorizationURL.host == "api.sonos.com" else {
            throw SonosAuthClientError.invalidAuthorizationResponse
        }

        return response
    }

    func oauthStatus(loginId: String) async throws -> SonosOAuthStatusResponse {
        guard loginId.isEmpty == false else {
            throw SonosAuthClientError.invalidLoginId
        }

        return try await request(
            .get,
            path: "oauth/status/\(loginId)",
            body: Optional<EmptyAuthRequest>.none
        )
    }

    func token(loginId: String? = nil) async throws -> SonosBrokerTokenResponse {
        let body = loginId.map { SonosBrokerTokenRequest(loginId: $0) }
        let response: SonosBrokerTokenResponse = try await request(
            .post,
            path: "token",
            body: body ?? SonosBrokerTokenRequest(loginId: nil)
        )

        guard response.accessToken.isEmpty == false,
              response.expiresAt > .now,
              response.tokenType.localizedCaseInsensitiveCompare("Bearer") == .orderedSame else {
            throw SonosAuthClientError.invalidTokenResponse
        }

        return response
    }

    private func request<Body: Encodable, Response: Decodable>(
        _ method: AuthHTTPMethod,
        path: String,
        body: Body?
    ) async throws -> Response {
        try throttle.check()
        guard configuration.baseURL.scheme == "https" else {
            throw SonosAuthClientError.insecureBaseURL
        }

        let url = configuration.baseURL.appending(path: path)
        guard url.scheme == "https", url.host == configuration.baseURL.host else {
            throw SonosAuthClientError.insecureBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SonosAuthClientError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw throttle.recordLimit(httpResponse, data: data)
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw SonosAuthClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        throttle.recordSuccess()
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw SonosAuthClientError.invalidResponse
        }
    }
}

struct SonosAuthHealthResponse: Decodable, Sendable {
    let status: String
    let oauthConfigured: Bool

    private enum CodingKeys: String, CodingKey {
        case status
        case oauthConfigured = "oauth_configured"
    }
}

struct SonosOAuthStartResponse: Decodable, Sendable {
    let loginId: String
    let authorizationURL: URL
    let expiresIn: Int

    private enum CodingKeys: String, CodingKey {
        case loginId = "login_id"
        case authorizationURL = "authorization_url"
        case expiresIn = "expires_in"
    }
}

struct SonosOAuthStatusResponse: Decodable, Sendable {
    let status: SonosOAuthStatus
}

enum SonosOAuthStatus: String, Decodable, Sendable {
    case pending
    case complete
    case failed
}

private struct SonosBrokerTokenRequest: Encodable {
    let loginId: String?

    private enum CodingKeys: String, CodingKey {
        case loginId = "login_id"
    }
}

struct SonosBrokerTokenResponse: Decodable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresAt: Date
    let brokerSessionId: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresAt = "expires_at"
        case expiresIn = "expires_in"
        case brokerSessionId = "broker_session_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        tokenType = try container.decode(String.self, forKey: .tokenType)
        if let timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .expiresAt) {
            expiresAt = Date(timeIntervalSince1970: timestamp)
        } else {
            expiresAt = Date().addingTimeInterval(try container.decode(TimeInterval.self, forKey: .expiresIn))
        }
        brokerSessionId = try container.decodeIfPresent(String.self, forKey: .brokerSessionId)
    }

    func credentials(fallbackSessionId: String) -> SonosStoredCredentials {
        let sessionId = brokerSessionId?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SonosStoredCredentials(
            brokerSessionId: sessionId.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackSessionId,
            accessToken: accessToken,
            accessTokenExpiresAt: expiresAt
        )
    }
}

enum SonosAuthClientError: LocalizedError {
    case insecureBaseURL
    case invalidAuthorizationResponse
    case invalidLoginId
    case invalidResponse
    case invalidTokenResponse
    case requestFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .insecureBaseURL:
            "Die Sonos-Anmeldung ist unsicher konfiguriert."
        case .invalidAuthorizationResponse:
            "Die Sonos-Anmeldung konnte nicht gestartet werden."
        case .invalidLoginId:
            "Die Sonos-Anmeldung ist ungültig."
        case .invalidResponse, .invalidTokenResponse:
            "Der Sonos-Dienst hat unerwartet geantwortet."
        case let .requestFailed(statusCode):
            Self.userMessage(for: statusCode)
        }
    }

    private static func userMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 401:
            "Die App muss erneut autorisiert werden."
        case 503:
            "Die Sonos-Anmeldung ist vorübergehend nicht verfügbar."
        default:
            "Keine Verbindung zum Sonos-Dienst."
        }
    }
}

private enum AuthHTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

private struct EmptyAuthRequest: Encodable {}

private final class NoRedirectURLSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
