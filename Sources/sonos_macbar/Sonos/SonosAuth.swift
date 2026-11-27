import Foundation

actor SonosAuth {
    private let authClient: SonosAuthClient
    private let tokenStore: SonosTokenStore
    private var cachedAccessToken: String?
    private var cachedAccessTokenExpiry: Date?
    private var tokenTask: Task<String, any Error>?
    private var isDisconnecting = false

    init(
        authClient: SonosAuthClient = SonosAuthClient(),
        tokenStore: SonosTokenStore = SonosTokenStore()
    ) {
        self.authClient = authClient
        self.tokenStore = tokenStore
    }

    func accessToken(replacing rejectedToken: String? = nil) async throws -> String {
        guard !isDisconnecting else { throw CancellationError() }
        if let tokenTask { return try await tokenTask.value }
        if let cachedAccessToken, cachedAccessToken != rejectedToken,
           cachedAccessTokenExpiry.map({ $0 > Date().addingTimeInterval(120) }) ?? true {
            return cachedAccessToken
        }

        let task = Task { try await loadAccessToken(replacing: rejectedToken) }
        tokenTask = task
        defer { tokenTask = nil }
        return try await task.value
    }

    private func loadAccessToken(replacing rejectedToken: String?) async throws -> String {
        let credentials = try await tokenStore.savedCredentials()
        if let credentials, let token = credentials.validAccessToken, token != rejectedToken {
            cacheAccessToken(token, expiresAt: credentials.accessTokenExpiresAt)
            return token
        }

        if credentials == nil, let token = tokenStore.developmentAccessToken(), token != rejectedToken {
            cacheAccessToken(token, expiresAt: nil)
            return token
        }

        let sessionId: String?
        if let credentials {
            sessionId = credentials.brokerSessionId
        } else {
            sessionId = try await tokenStore.legacyBrokerSessionId()
        }
        guard let sessionId else { throw SonosAPIError.credentialsRequired }

        let renewed: SonosBrokerTokenResponse
        do {
            renewed = try await authClient.token(loginId: sessionId)
        } catch SonosAuthClientError.requestFailed(let status) where [401, 404, 410].contains(status) {
            throw SonosAPIError.credentialsRequired
        }
        try Task.checkCancellation()
        let updated = renewed.credentials(fallbackSessionId: sessionId)
        try await tokenStore.saveCredentials(updated)
        cacheAccessToken(renewed.accessToken, expiresAt: renewed.expiresAt)
        return renewed.accessToken
    }

    func cacheAccessToken(_ token: String, expiresAt: Date?) {
        cachedAccessToken = token
        cachedAccessTokenExpiry = expiresAt
    }

    func disconnect() async throws {
        isDisconnecting = true
        defer { isDisconnecting = false }
        tokenTask?.cancel()
        _ = await tokenTask?.result
        try await tokenStore.deleteAllSonosCredentials()
        cachedAccessToken = nil
        cachedAccessTokenExpiry = nil
    }
}
