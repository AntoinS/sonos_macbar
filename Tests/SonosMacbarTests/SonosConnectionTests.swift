import Foundation
import Testing
import UPnPCast
import os
@testable import sonos_macbar

@Suite(.serialized)
struct SonosConnectionTests {
    @Test func localPollingUpdatesVolumeTwicePerSecond() {
        var polling = SonosPollingSchedule(mode: .local)
        let now = ContinuousClock.now
        polling.beginRoomRefresh(at: now)
        #expect(polling.timeUntilNextRead(at: now) == .milliseconds(500))
        for milliseconds in [500, 1000, 1500] {
            let time = now.advanced(by: .milliseconds(milliseconds))
            #expect(polling.timeUntilNextRead(at: time) == .zero)
            let includeSource = polling.beginPlayerRefresh(at: time)
            #expect(!includeSource)
        }
        let includeSource = polling.beginPlayerRefresh(at: now.advanced(by: .seconds(2)))
        #expect(includeSource)
    }

    @Test @MainActor func localModeFindsAndControlsTheBeamWithoutASession() async throws {
        let location = try #require(URL(string: "http://192.168.1.12:1400/xml/device_description.xml"))
        let description = """
            <root><device><UDN>uuid:RINCON_BEAM</UDN><modelName>Sonos Beam</modelName><serviceList>
            <service><serviceType>urn:schemas-upnp-org:service:ZoneGroupTopology:1</serviceType><controlURL>/ZoneGroupTopology/Control</controlURL></service>
            <service><serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType><controlURL>/MediaRenderer/RenderingControl/Control</controlURL></service>
            <service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><controlURL>/MediaRenderer/AVTransport/Control</controlURL></service>
            </serviceList></device></root>
            """
        let device = try UPnPDevice.parse(Data(description.utf8), descriptionURL: location)
        let topology = """
            <ZoneGroups><ZoneGroup Coordinator="RINCON_BEAM">
              <ZoneGroupMember UUID="RINCON_BEAM" ZoneName="Living Room"><Satellite UUID="RINCON_SUB"/></ZoneGroupMember>
              <ZoneGroupMember UUID="RINCON_HIDDEN" ZoneName="Hidden" Invisible="1"/>
            </ZoneGroup></ZoneGroups>
            """
        #expect(try SonosLocalService.rooms(from: topology).map(\.id) == ["RINCON_BEAM"])
        let output = [
            "GetZoneGroupState": "<ZoneGroupState>\(xmlEscape(topology))</ZoneGroupState>",
            "GetVolume": "<CurrentVolume>35</CurrentVolume>",
            "GetMute": "<CurrentMute>0</CurrentMute>",
            "GetPositionInfo": "<TrackURI>x-sonos-spotify:abc</TrackURI>",
            "GetEQ": "<CurrentValue>0</CurrentValue>",
            "SetVolume": "",
            "SetMute": "",
            "SetEQ": ""
        ]
        StubSonosHTTP.reset(actions: output.mapValues { .init(status: 200, body: $0) })
        let service = SonosLocalService(session: StubSonosHTTP.session()) { _ in [device] }
        let state = SonosState(service: service, connectionMode: .local)

        await state.loadPlayers()
        #expect(!state.canConnectSonos)
        let room = try #require(state.selectedPlayer)
        #expect(room.roomName == "Living Room")
        #expect(room.playbackSource == "Spotify")
        #expect(room.volume == 35)
        #expect(room.supportsEnhanceDialog && room.supportsNightMode)
        #expect(state.connectionStatus(for: .german) == "Lokal verbunden")

        await state.commitVolume(38)
        await state.setMuted(true)
        await state.setNightMode(true)
        #expect(state.selectedPlayer?.volume == 38)
        #expect(state.selectedPlayer?.muted == true)
        #expect(state.selectedPlayer?.nightMode == true)
        #expect(StubSonosHTTP.hosts == ["192.168.1.12"])
    }

    @Test func pollingKeepsItsCooldownAcrossPopoverReopens() {
        var polling = SonosPollingSchedule()
        let now = ContinuousClock.now
        #expect(polling.timeUntilNextRead(at: now) == .zero)
        polling.beginRoomRefresh(at: now)
        #expect(polling.timeUntilNextRead(at: now.advanced(by: .seconds(3))) == .seconds(12))

        for seconds in [15, 30, 45] {
            let time = now.advanced(by: .seconds(seconds))
            #expect(polling.timeUntilNextRead(at: time) == .zero)
            let includeSource = polling.beginPlayerRefresh(at: time)
            #expect(!includeSource)
        }
        let includeSource = polling.beginPlayerRefresh(at: now.advanced(by: .seconds(60)))
        #expect(includeSource)
        #expect(polling.timeUntilNextRead(at: now.advanced(by: .seconds(61))) == .seconds(14))
    }

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
            #expect(state.authState == .sessionUnavailable)
            let retryAt = try #require(state.rateLimitedUntil)
            #expect(state.connectionIssue == .rateLimited(retryAt: retryAt))
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
            let retryAt = try #require(state.rateLimitedUntil)
            #expect(state.connectionIssue == .rateLimited(retryAt: retryAt))
            #expect(state.connectionStatus(for: .german) == "Sonos-Anfragelimit (429)")
            await #expect(throws: SonosRateLimited.self) {
                _ = try await service.fetchPlayers()
            }
            #expect(StubSonosHTTP.requestCount == 2)
        }
    }

    @Test @MainActor func cloudFailureHasItsOwnStatus() async throws {
        try await withExpiredCredentials { store in
            StubSonosHTTP.reset([
                .init(status: 200, body: #"{"access_token":"fresh","expires_in":86400,"token_type":"Bearer"}"#),
                .init(status: 503)
            ])
            let session = StubSonosHTTP.session()
            let client = SonosAuthClient(session: session)
            let auth = SonosAuth(authClient: client, tokenStore: store)
            let coordinator = SonosOAuthCoordinator(authClient: client, tokenStore: store, auth: auth)
            let state = SonosState(
                service: SonosService(auth: auth, session: session),
                tokenStore: store,
                oauthCoordinator: coordinator
            )

            await state.loadPlayers()
            #expect(state.isConnected)
            #expect(state.connectionIssue == .cloudRequestFailed)
            #expect(state.connectionStatus(for: .german) == "Cloud-Steuerung gestört")
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
        var actions: [String: Reply] = [:]
        var hosts: Set<String> = []
        var requestCount = 0
    }

    private static let state = OSAllocatedUnfairLock(initialState: State(replies: []))

    static var requestCount: Int { state.withLock { $0.requestCount } }
    static var hosts: Set<String> { state.withLock { $0.hosts } }

    static func reset(_ replies: [Reply]) {
        state.withLock { $0 = State(replies: replies) }
    }

    static func reset(actions: [String: Reply]) {
        state.withLock { $0 = State(replies: [], actions: actions) }
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
            if let host = request.url?.host { state.hosts.insert(host) }
            if let header = request.value(forHTTPHeaderField: "SOAPACTION"),
               let action = header.split(separator: "#").last?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
               var routed = state.actions[action] {
                routed.body = "<Envelope><Body><\(action)Response>\(routed.body)</\(action)Response></Body></Envelope>"
                return routed
            }
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
