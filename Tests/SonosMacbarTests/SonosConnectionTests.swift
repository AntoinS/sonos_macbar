import Foundation
import Testing
import os
@testable import sonos_macbar

@Suite(.serialized)
struct SonosConnectionTests {
    @Test func retryAfterAppliesToOtherRequestsUntilDeadline() throws {
        var throttle = SonosRequestThrottle()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://api.ws.sonos.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "32"]
        ))
        let limit = throttle.recordLimit(response, data: Data(), now: now)
        #expect(limit.retryAt == now.addingTimeInterval(32))
        throttle.recordSuccess(now: now.addingTimeInterval(1))
        #expect(throws: SonosRateLimited.self) {
            try throttle.check(now: now.addingTimeInterval(31))
        }
        try throttle.check(now: now.addingTimeInterval(32))
    }

    @Test func dailyQuotaWaitsUntilMidnightUTC() throws {
        var throttle = SonosRequestThrottle()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://api.ws.sonos.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: nil
        ))
        let body = Data(#"{"error":"Quota violation.","allowed quota":"20000 per day per user"}"#.utf8)
        let limit = throttle.recordLimit(response, data: body, now: now)
        let nextDay = (floor(now.timeIntervalSince1970 / 86_400) + 1) * 86_400
        #expect(limit.retryAt == Date(timeIntervalSince1970: nextDay))
    }

    @Test func expiredSessionRefreshesOnceAndStoresTheNewSessionID() async throws {
        try await withExpiredCredentials { store in
            StubSonosHTTP.reset([
                .init(status: 200, body: #"{"access_token":"fresh","expires_in":86400,"token_type":"Bearer","broker_session_id":"new-session"}"#)
            ])
            let auth = SonosAuth(authClient: SonosAuthClient(session: StubSonosHTTP.session()), tokenStore: store)
            async let first = auth.accessToken()
            async let second = auth.accessToken()
            let tokens = try await [first, second]
            #expect(tokens == ["fresh", "fresh"])
            #expect(StubSonosHTTP.requestCount == 1)
            let saved = try await store.savedCredentials()
            #expect(saved?.brokerSessionId == "new-session")
            #expect(saved?.validAccessToken == "fresh")
        }
    }

    @Test @MainActor func brokerRateLimitKeepsTheSessionAndRetriesWithIt() async throws {
        try await withExpiredCredentials { store in
            StubSonosHTTP.reset([
                .init(status: 429, headers: ["Retry-After": "1"]),
                .init(status: 200, body: #"{"access_token":"fresh","expires_in":86400,"token_type":"Bearer"}"#),
                .init(status: 200, body: #"{"households":[{"id":"household"}]}"#),
                .init(status: 200, body: #"{"players":[],"groups":[]}"#)
            ])
            let session = StubSonosHTTP.session()
            let client = SonosAuthClient(session: session)
            let auth = SonosAuth(authClient: client, tokenStore: store)
            let coordinator = SonosOAuthCoordinator(authClient: client, tokenStore: store, auth: auth)
            let service = SonosService(auth: auth, session: session)
            let state = SonosState(service: service, tokenStore: store, oauthCoordinator: coordinator)

            await state.loadPlayers()
            #expect(state.authState == .offline)
            #expect(state.rateLimitedUntil != nil)
            #expect(!state.canConnectSonos)
            #expect(try await store.savedCredentials()?.brokerSessionId == "old-session")

            await state.loadPlayers()
            #expect(StubSonosHTTP.requestCount == 1)

            try await Task.sleep(for: .seconds(1.1))
            await state.loadPlayers()
            #expect(state.isConnected)
            #expect(state.rateLimitedUntil == nil)
            #expect(StubSonosHTTP.requestCount == 4)
        }
    }

    @Test @MainActor func controlRateLimitKeepsTheConnectedState() async throws {
        try await withExpiredCredentials { store in
            StubSonosHTTP.reset([
                .init(status: 200, body: #"{"access_token":"fresh","expires_in":86400,"token_type":"Bearer"}"#),
                .init(status: 429, headers: ["Retry-After": "30"])
            ])
            let session = StubSonosHTTP.session()
            let client = SonosAuthClient(session: session)
            let auth = SonosAuth(authClient: client, tokenStore: store)
            let coordinator = SonosOAuthCoordinator(authClient: client, tokenStore: store, auth: auth)
            let service = SonosService(auth: auth, session: session)
            let state = SonosState(service: service, tokenStore: store, oauthCoordinator: coordinator)

            await state.loadPlayers()
            #expect(state.isConnected)
            #expect(state.showsConnectionView)
            #expect(!state.canConnectSonos)
            #expect(state.rateLimitedUntil != nil)
            await #expect(throws: SonosRateLimited.self) {
                _ = try await service.fetchPlayers()
            }
            #expect(StubSonosHTTP.requestCount == 2)
        }
    }

    @Test func rejectedSessionRequiresAuthorization() async throws {
        try await withExpiredCredentials { store in
            StubSonosHTTP.reset([.init(status: 401)])
            let auth = SonosAuth(authClient: SonosAuthClient(session: StubSonosHTTP.session()), tokenStore: store)
            do {
                _ = try await auth.accessToken()
                Issue.record("A rejected session must require authorization")
            } catch SonosAPIError.credentialsRequired {}
        }
    }

    private func withExpiredCredentials(
        isolation: isolated (any Actor)? = #isolation,
        _ operation: (SonosTokenStore) async throws -> Void
    ) async throws {
        let store = SonosTokenStore(environment: [:], keychainAccount: "tests.\(UUID())")
        try await store.saveCredentials(.init(
            brokerSessionId: "old-session",
            accessToken: "expired",
            accessTokenExpiresAt: .distantPast
        ))
        do {
            try await operation(store)
        } catch {
            try? await store.deleteAllSonosCredentials()
            throw error
        }
        try await store.deleteAllSonosCredentials()
    }
}

private final class StubSonosHTTP: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        let status: Int
        var headers: [String: String] = [:]
        var body = ""
    }

    private struct State {
        var replies: [Reply]
        var requestCount = 0
    }

    private static let state = OSAllocatedUnfairLock(initialState: State(replies: []))

    static var requestCount: Int { state.withLock { $0.requestCount } }

    static func reset(_ replies: [Reply]) {
        state.withLock { $0 = State(replies: replies) }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply = Self.state.withLock { state -> Reply? in
            state.requestCount += 1
            return state.replies.isEmpty ? nil : state.replies.removeFirst()
        }
        guard let reply, let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
