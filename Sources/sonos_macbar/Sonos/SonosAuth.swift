import Foundation

struct SonosAuth {
    let authClient: SonosAuthClient
    let tokenStore: SonosTokenStore

    init(
        authClient: SonosAuthClient = SonosAuthClient(),
        tokenStore: SonosTokenStore = SonosTokenStore()
    ) {
        self.authClient = authClient
        self.tokenStore = tokenStore
    }

    func accessToken() async throws -> String {
        if let token = await tokenStore.accessToken() {
            return token
        }

        guard let brokerSessionId = await tokenStore.brokerSessionId() else {
            throw SonosAPIError.credentialsRequired
        }

        let brokerToken = try await authClient.token(loginId: brokerSessionId)
        try await tokenStore.saveAccessToken(brokerToken.accessToken, expiresAt: brokerToken.expiresAt)
        return brokerToken.accessToken
    }

    func refreshAccessToken() async throws -> String {
        try await tokenStore.deleteSavedAccessToken()
        guard let brokerSessionId = await tokenStore.brokerSessionId() else {
            throw SonosAPIError.credentialsRequired
        }

        let brokerToken = try await authClient.token(loginId: brokerSessionId)
        try await tokenStore.saveAccessToken(brokerToken.accessToken, expiresAt: brokerToken.expiresAt)
        return brokerToken.accessToken
    }
}
