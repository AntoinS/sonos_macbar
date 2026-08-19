import Foundation

actor SonosService: SonosAPI {
    private let baseURL = URL(string: "https://api.ws.sonos.com/control/api/v1")!
    private let auth: SonosAuth
    private var cachedPlayers: [SonosPlayer] = []

    init(auth: SonosAuth = SonosAuth()) {
        self.auth = auth
    }

    func fetchPlayers() async throws -> [SonosPlayer] {
        let households: HouseholdsResponse = try await send(.get, path: "households")

        guard let householdID = households.households.first?.id else {
            throw SonosAPIError.noHouseholdFound
        }

        let groupsResponse: GroupsResponse = try await send(.get, path: "households/\(householdID)/groups")

        let players = await withTaskGroup(of: SonosPlayer?.self) { group in
            for player in groupsResponse.players {
                group.addTask { [self] in
                    await makePlayer(from: player)
                }
            }

            var resolvedPlayers: [SonosPlayer] = []
            for await player in group {
                if let player {
                    resolvedPlayers.append(player)
                }
            }

            return resolvedPlayers.sorted { $0.roomName.localizedCaseInsensitiveCompare($1.roomName) == .orderedAscending }
        }

        cachedPlayers = players
        return players
    }

    func setVolume(_ volume: Int, for playerID: SonosPlayer.ID) async throws -> SonosPlayer {
        try await send(.post, path: "players/\(playerID)/playerVolume", body: SetVolumeRequest(volume: volume, muted: nil))
        return try updateCachedPlayer(playerID) { player in
            player.volume = min(100, max(0, volume))
            player.muted = false
        }
    }

    func setMuted(_ isMuted: Bool, for playerID: SonosPlayer.ID) async throws -> SonosPlayer {
        try await send(.post, path: "players/\(playerID)/playerVolume", body: SetVolumeRequest(volume: nil, muted: isMuted))
        return try updateCachedPlayer(playerID) { player in
            player.muted = isMuted
        }
    }

    func setEnhanceDialog(_ isEnabled: Bool, for playerID: SonosPlayer.ID) async throws -> SonosPlayer {
        try await send(.post, path: "players/\(playerID)/homeTheater/options", body: HomeTheaterOptionsRequest(nightMode: nil, enhanceDialog: isEnabled))
        return try updateCachedPlayer(playerID) { player in
            player.enhanceDialog = isEnabled
        }
    }

    func setNightMode(_ isEnabled: Bool, for playerID: SonosPlayer.ID) async throws -> SonosPlayer {
        try await send(.post, path: "players/\(playerID)/homeTheater/options", body: HomeTheaterOptionsRequest(nightMode: isEnabled, enhanceDialog: nil))
        return try updateCachedPlayer(playerID) { player in
            player.nightMode = isEnabled
        }
    }

    private func makePlayer(from player: SonosPlayerResponse) async -> SonosPlayer {
        async let volume = playerVolume(for: player.id)
        async let options = homeTheaterOptions(for: player.id, isHomeTheaterCapable: player.capabilities.contains("HT_PLAYBACK"))

        let resolvedVolume = await volume
        let resolvedOptions = await options

        return SonosPlayer(
            id: player.id,
            roomName: player.name,
            deviceName: player.iconDisplayName,
            volume: resolvedVolume?.volume ?? 0,
            muted: resolvedVolume?.muted ?? false,
            enhanceDialog: resolvedOptions?.enhanceDialog ?? false,
            nightMode: resolvedOptions?.nightMode ?? false,
            supportsEnhanceDialog: resolvedOptions != nil,
            supportsNightMode: resolvedOptions != nil
        )
    }

    private func playerVolume(for playerID: SonosPlayer.ID) async -> PlayerVolumeResponse? {
        try? await send(.get, path: "players/\(playerID)/playerVolume")
    }

    private func homeTheaterOptions(for playerID: SonosPlayer.ID, isHomeTheaterCapable: Bool) async -> HomeTheaterOptionsResponse? {
        guard isHomeTheaterCapable else { return nil }
        return try? await send(.get, path: "players/\(playerID)/homeTheater/options")
    }

    private func updateCachedPlayer(
        _ playerID: SonosPlayer.ID,
        mutation: (inout SonosPlayer) -> Void
    ) throws -> SonosPlayer {
        guard let index = cachedPlayers.firstIndex(where: { $0.id == playerID }) else {
            throw SonosAPIError.playerNotFound
        }

        mutation(&cachedPlayers[index])
        return cachedPlayers[index]
    }

    @discardableResult
    private func send<Body: Encodable>(_ method: HTTPMethod, path: String, body: Body?) async throws -> EmptyResponse {
        let _: EmptyResponse = try await request(method, path: path, body: body)
        return EmptyResponse()
    }

    private func send<Response: Decodable>(_ method: HTTPMethod, path: String) async throws -> Response {
        try await request(method, path: path, body: Optional<EmptyRequest>.none)
    }

    private func request<Body: Encodable, Response: Decodable>(_ method: HTTPMethod, path: String, body: Body?) async throws -> Response {
        let token = try await auth.accessToken()
        do {
            return try await request(method, path: path, body: body, token: token)
        } catch let error as SonosAPIError {
            guard case .requestFailed(statusCode: 401, _) = error else {
                throw error
            }

            let refreshedToken = try await auth.refreshAccessToken()
            return try await request(method, path: path, body: body, token: refreshedToken)
        }
    }

    private func request<Body: Encodable, Response: Decodable>(
        _ method: HTTPMethod,
        path: String,
        body: Body?,
        token: String
    ) async throws -> Response {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Sonos-Corr-Id")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SonosAPIError.requestFailed(statusCode: -1, message: nil)
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let error = try? JSONDecoder().decode(SonosErrorResponse.self, from: data)
            throw SonosAPIError.requestFailed(statusCode: httpResponse.statusCode, message: error?.message)
        }

        guard !data.isEmpty else {
            return EmptyResponse() as! Response
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SonosAPIError.invalidResponse
        }
    }
}

private enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

private struct EmptyRequest: Encodable {}
private struct EmptyResponse: Decodable {
    init() {}
}

private struct HouseholdsResponse: Decodable {
    let households: [HouseholdResponse]

    private enum CodingKeys: String, CodingKey {
        case households
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        households = try container.decodeIfPresent([HouseholdResponse].self, forKey: .households) ?? []
    }
}

private struct HouseholdResponse: Decodable {
    let id: String
}

private struct GroupsResponse: Decodable {
    let players: [SonosPlayerResponse]

    private enum CodingKeys: String, CodingKey {
        case players
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        players = try container.decodeIfPresent([SonosPlayerResponse].self, forKey: .players) ?? []
    }
}

private struct SonosPlayerResponse: Decodable {
    let id: String
    let name: String
    let icon: String?
    let capabilities: [String]

    var iconDisplayName: String {
        guard let icon, !icon.isEmpty else {
            return "Sonos Speaker"
        }

        return icon
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case icon
        case capabilities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Sonos"
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
    }
}

private struct PlayerVolumeResponse: Decodable {
    let volume: Int
    let muted: Bool

    private enum CodingKeys: String, CodingKey {
        case volume
        case muted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        volume = try container.decodeIfPresent(Int.self, forKey: .volume) ?? 0
        muted = try container.decodeIfPresent(Bool.self, forKey: .muted) ?? false
    }
}

private struct SetVolumeRequest: Encodable {
    let volume: Int?
    let muted: Bool?
}

private struct HomeTheaterOptionsRequest: Encodable {
    let nightMode: Bool?
    let enhanceDialog: Bool?
}

private struct HomeTheaterOptionsResponse: Decodable {
    let nightMode: Bool
    let enhanceDialog: Bool
}

private struct SonosErrorResponse: Decodable {
    let globalError: GlobalError?

    var message: String? {
        globalError?.reason
    }

    struct GlobalError: Decodable {
        let reason: String?
    }
}
