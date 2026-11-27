import Foundation

actor SonosService: SonosAPI {
    private let baseURL = URL(string: "https://api.ws.sonos.com/control/api/v1")!
    private let auth: SonosAuth
    private let session: URLSession
    private var cachedPlayers: [SonosPlayer] = []
    private var throttle = SonosRequestThrottle()

    init(auth: SonosAuth = SonosAuth(), session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    func fetchPlayers() async throws -> [SonosPlayer] {
        let households: HouseholdsResponse = try await send(.get, path: "households")

        guard let householdID = households.households.first?.id else {
            throw SonosAPIError.noHouseholdFound
        }

        let groupsResponse: GroupsResponse = try await send(.get, path: "households/\(householdID)/groups")

        let groupIDByPlayerID = groupsResponse.groupIDByPlayerID

        let players = await withTaskGroup(of: SonosPlayer?.self) { group in
            for player in groupsResponse.players {
                let groupID = groupIDByPlayerID[player.id]
                group.addTask { [self] in
                    await makePlayer(from: player, groupID: groupID)
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

    func refreshPlayerState(_ player: SonosPlayer, includingSource: Bool) async throws -> SonosPlayer {
        let volume = try await currentPlayerVolume(for: player.id)
        let source = includingSource ? await playbackSource(for: player.groupID) : nil

        return try updateCachedPlayer(player.id) { cachedPlayer in
            cachedPlayer.volume = volume.volume
            cachedPlayer.muted = volume.muted
            if includingSource {
                cachedPlayer.playbackSource = source ?? player.playbackSource
            }
        }
    }

    private func makePlayer(from player: SonosPlayerResponse, groupID: String?) async -> SonosPlayer {
        async let volume = playerVolume(for: player.id)
        async let options = homeTheaterOptions(for: player.id, isHomeTheaterCapable: player.capabilities.contains("HT_PLAYBACK"))
        async let source = playbackSource(for: groupID)

        let resolvedVolume = await volume
        let resolvedOptions = await options
        let resolvedSource = await source

        return SonosPlayer(
            id: player.id,
            groupID: groupID,
            roomName: player.name,
            deviceName: player.iconDisplayName,
            playbackSource: resolvedSource,
            volume: resolvedVolume?.volume ?? 0,
            muted: resolvedVolume?.muted ?? false,
            enhanceDialog: resolvedOptions?.enhanceDialog ?? false,
            nightMode: resolvedOptions?.nightMode ?? false,
            supportsEnhanceDialog: resolvedOptions != nil,
            supportsNightMode: resolvedOptions != nil
        )
    }

    private func playerVolume(for playerID: SonosPlayer.ID) async -> PlayerVolumeResponse? {
        try? await currentPlayerVolume(for: playerID)
    }

    private func currentPlayerVolume(for playerID: SonosPlayer.ID) async throws -> PlayerVolumeResponse {
        try await send(.get, path: "players/\(playerID)/playerVolume")
    }

    private func playbackSource(for groupID: String?) async -> String? {
        guard let groupID else { return nil }
        let metadata: PlaybackMetadataResponse? = try? await send(.get, path: "groups/\(groupID)/playbackMetadata")
        return metadata?.sourceName
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
        try throttle.check()
        let token = try await auth.accessToken()
        do {
            return try await request(method, path: path, body: body, token: token)
        } catch let error as SonosAPIError {
            guard case .requestFailed(statusCode: 401, _) = error else {
                throw error
            }

            let refreshedToken = try await auth.accessToken(replacing: token)
            do {
                return try await request(method, path: path, body: body, token: refreshedToken)
            } catch SonosAPIError.requestFailed(statusCode: 401, _) {
                throw SonosAPIError.credentialsRequired
            }
        }
    }

    private func request<Body: Encodable, Response: Decodable>(
        _ method: HTTPMethod,
        path: String,
        body: Body?,
        token: String
    ) async throws -> Response {
        try Task.checkCancellation()
        try throttle.check()
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

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SonosAPIError.requestFailed(statusCode: -1, message: nil)
        }

        if httpResponse.statusCode == 429 {
            throw throttle.recordLimit(httpResponse, data: data)
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let error = try? JSONDecoder().decode(SonosErrorResponse.self, from: data)
            throw SonosAPIError.requestFailed(statusCode: httpResponse.statusCode, message: error?.message)
        }

        throttle.recordSuccess()
        if data.isEmpty, let empty = EmptyResponse() as? Response {
            return empty
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
    let groups: [SonosGroupResponse]
    let players: [SonosPlayerResponse]

    var groupIDByPlayerID: [String: String] {
        groups.reduce(into: [:]) { result, group in
            for playerID in group.playerIDs {
                result[playerID] = group.id
            }

            if let coordinatorID = group.coordinatorID {
                result[coordinatorID] = group.id
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case groups
        case players
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = try container.decodeIfPresent([SonosGroupResponse].self, forKey: .groups) ?? []
        players = try container.decodeIfPresent([SonosPlayerResponse].self, forKey: .players) ?? []
    }
}

private struct SonosGroupResponse: Decodable {
    let id: String
    let coordinatorID: String?
    let playerIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case coordinatorID = "coordinatorId"
        case playerIDs = "playerIds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        coordinatorID = try container.decodeIfPresent(String.self, forKey: .coordinatorID)
        playerIDs = try container.decodeIfPresent([String].self, forKey: .playerIDs) ?? []
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

private struct PlaybackMetadataResponse: Decodable {
    let container: PlaybackContainer?
    let currentItem: PlaybackItem?
    let streamInfo: String?

    var sourceName: String? {
        firstNonEmpty(container?.sourceName, currentItem?.sourceName, streamInfo)
    }
}

private struct PlaybackContainer: Decodable {
    let name: String?
    let type: String?
    let service: PlaybackService?

    var sourceName: String? {
        firstNonEmpty(service?.name, name, normalizedType)
    }

    private var normalizedType: String? {
        guard let type, !type.isEmpty else { return nil }
        return type
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .capitalized
    }
}

private struct PlaybackItem: Decodable {
    let service: PlaybackService?
    let track: PlaybackTrack?
    let streamInfo: String?

    var sourceName: String? {
        firstNonEmpty(service?.name, track?.service?.name, streamInfo)
    }
}

private struct PlaybackTrack: Decodable {
    let service: PlaybackService?
}

private struct PlaybackService: Decodable {
    let name: String?
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

private func firstNonEmpty(_ values: String?...) -> String? {
    values.compactMap { value -> String? in
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }.first
}
