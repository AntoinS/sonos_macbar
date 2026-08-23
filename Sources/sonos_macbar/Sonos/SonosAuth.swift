import Foundation

actor SonosAuth {
    let authClient: SonosAuthClient
    let tokenStore: SonosTokenStore
    private var cachedAccessToken: String?
    private var cachedAccessTokenExpiry: Date?

    init(
        authClient: SonosAuthClient = SonosAuthClient(),
        tokenStore: SonosTokenStore = SonosTokenStore()
    ) {
        self.authClient = authClient
        self.tokenStore = tokenStore
    }

    func accessToken() async throws -> String {
        if let cachedAccessToken, isCachedAccessTokenValid {
            return cachedAccessToken
        }

        if let credentials = await tokenStore.savedCredentials() {
            if let token = credentials.validAccessToken {
                cacheAccessToken(token, expiresAt: credentials.accessTokenExpiresAt)
                return token
            }

            let brokerToken = try await authClient.token(loginId: credentials.brokerSessionId)
            try await tokenStore.saveCredentials(
                SonosStoredCredentials(
                    brokerSessionId: credentials.brokerSessionId,
                    accessToken: brokerToken.accessToken,
                    accessTokenExpiresAt: brokerToken.expiresAt
                )
            )
            cacheAccessToken(brokerToken.accessToken, expiresAt: brokerToken.expiresAt)
            return brokerToken.accessToken
        }

        if let token = tokenStore.developmentAccessToken() {
            cacheAccessToken(token, expiresAt: nil)
            return token
        }

        guard let brokerSessionId = await tokenStore.legacyBrokerSessionId() else {
            throw SonosAPIError.credentialsRequired
        }

        let brokerToken = try await authClient.token(loginId: brokerSessionId)
        try await tokenStore.saveCredentials(
            SonosStoredCredentials(
                brokerSessionId: brokerSessionId,
                accessToken: brokerToken.accessToken,
                accessTokenExpiresAt: brokerToken.expiresAt
            )
        )
        cacheAccessToken(brokerToken.accessToken, expiresAt: brokerToken.expiresAt)
        return brokerToken.accessToken
    }

    func refreshAccessToken() async throws -> String {
        cachedAccessToken = nil
        cachedAccessTokenExpiry = nil

        let credentials = await tokenStore.savedCredentials()
        let brokerSessionId: String?
        if let storedBrokerSessionId = credentials?.brokerSessionId {
            brokerSessionId = storedBrokerSessionId
        } else {
            brokerSessionId = await tokenStore.legacyBrokerSessionId()
        }

        guard let brokerSessionId else {
            throw SonosAPIError.credentialsRequired
        }

        let brokerToken = try await authClient.token(loginId: brokerSessionId)
        try await tokenStore.saveCredentials(
            SonosStoredCredentials(
                brokerSessionId: brokerSessionId,
                accessToken: brokerToken.accessToken,
                accessTokenExpiresAt: brokerToken.expiresAt
            )
        )
        cacheAccessToken(brokerToken.accessToken, expiresAt: brokerToken.expiresAt)
        return brokerToken.accessToken
    }

    func cacheAccessToken(_ token: String, expiresAt: Date?) {
        cachedAccessToken = token
        cachedAccessTokenExpiry = expiresAt
    }

    func clearCachedAccessToken() {
        cachedAccessToken = nil
        cachedAccessTokenExpiry = nil
    }

    private var isCachedAccessTokenValid: Bool {
        guard let cachedAccessToken, !cachedAccessToken.isEmpty else { return false }
        guard let cachedAccessTokenExpiry else { return true }
        return cachedAccessTokenExpiry > Date().addingTimeInterval(120)
    }
}
