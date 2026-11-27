import Foundation
import UPnPCast

actor SonosLocalService: SonosAPI {
    struct Room: Equatable, Sendable {
        let id: String
        let name: String
        let coordinatorID: String?
    }

    private let session: URLSession
    private let soap: SOAPClient
    private let discover: @Sendable (URLSession) async throws -> [UPnPDevice]
    private var renderers: [String: MediaRenderer] = [:]
    private var players: [String: SonosPlayer] = [:]
    private var revisions: [String: Int] = [:]

    init(
        session: URLSession = SonosLocalDiscovery.localSession(),
        discover: @escaping @Sendable (URLSession) async throws -> [UPnPDevice] = SonosLocalDiscovery.discover
    ) {
        self.session = session
        self.soap = SOAPClient(session: session, timeout: 2)
        self.discover = discover
    }

    func fetchPlayers() async throws -> [SonosPlayer] {
        let devices = try await discover(session)
        let rooms = try await visibleRooms(from: devices)
        var available: [String: MediaRenderer] = [:]
        for device in devices {
            guard let renderer = try? MediaRenderer(device: device, soap: soap),
                  SonosLocalDiscovery.service(ofType: UPnPServiceType.avTransport, on: device) != nil,
                  SonosLocalDiscovery.service(ofType: UPnPServiceType.renderingControl, on: device) != nil else { continue }
            available[String(device.udn.dropFirst("uuid:".count)).uppercased()] = renderer
        }

        let loaded = await withTaskGroup(of: SonosPlayer?.self) { group in
            for room in rooms {
                guard let renderer = available[room.id] else { continue }
                let sourceRenderer = room.coordinatorID.flatMap { available[$0] } ?? renderer
                group.addTask { [self] in
                    try? await makePlayer(room: room, renderer: renderer, sourceRenderer: sourceRenderer)
                }
            }
            var result: [SonosPlayer] = []
            for await player in group {
                if let player { result.append(player) }
            }
            return result.sorted { $0.roomName.localizedStandardCompare($1.roomName) == .orderedAscending }
        }
        try Task.checkCancellation()
        guard !loaded.isEmpty else { throw SonosAPIError.playerNotFound }
        renderers = available
        players = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        return loaded
    }

    func refreshPlayerState(_ player: SonosPlayer, includingSource: Bool) async throws -> SonosPlayer {
        let renderer = try renderer(for: player.id)
        let revision = revisions[player.id, default: 0]
        let sourceRenderer = player.groupID.flatMap { renderers[$0] } ?? renderer
        async let volume = renderer.volume()
        async let muted = renderer.isMuted()
        async let source = includingSource ? playbackSource(on: sourceRenderer) : player.playbackSource
        async let dialog = includingSource && player.supportsEnhanceDialog ? readEQ("DialogLevel", on: renderer) : nil
        async let night = includingSource && player.supportsNightMode ? readEQ("NightMode", on: renderer) : nil
        let readings = try await (volume, muted, source, dialog, night)
        try Task.checkCancellation()
        return try update(player.id) { cached in
            guard revisions[player.id, default: 0] == revision else { return }
            cached.volume = readings.0
            cached.muted = readings.1
            if includingSource { cached.playbackSource = readings.2 }
            if let dialog = readings.3 { cached.enhanceDialog = dialog }
            if let night = readings.4 { cached.nightMode = night }
        }
    }

    func setVolume(_ volume: Int, for playerID: SonosPlayer.ID) async throws -> SonosPlayer {
        let renderer = try renderer(for: playerID)
        let desired = min(100, max(0, volume))
        let shouldUnmute = players[playerID]?.muted == true
        revisions[playerID, default: 0] += 1
        defer { revisions[playerID, default: 0] += 1 }
        try await renderer.setVolume(desired)
        if shouldUnmute { try await renderer.setMuted(false) }
        return try update(playerID) { player in
            player.volume = desired
            if shouldUnmute { player.muted = false }
        }
    }

    func setMuted(_ isMuted: Bool, for playerID: SonosPlayer.ID) async throws -> SonosPlayer {
        let renderer = try renderer(for: playerID)
        revisions[playerID, default: 0] += 1
        defer { revisions[playerID, default: 0] += 1 }
        try await renderer.setMuted(isMuted)
        return try update(playerID) { $0.muted = isMuted }
    }

    func setEnhanceDialog(_ isEnabled: Bool, for playerID: SonosPlayer.ID) async throws -> SonosPlayer {
        try await writeEQ("DialogLevel", enabled: isEnabled, playerID: playerID)
        return try update(playerID) { $0.enhanceDialog = isEnabled }
    }

    func setNightMode(_ isEnabled: Bool, for playerID: SonosPlayer.ID) async throws -> SonosPlayer {
        try await writeEQ("NightMode", enabled: isEnabled, playerID: playerID)
        return try update(playerID) { $0.nightMode = isEnabled }
    }

    private func renderer(for id: String) throws -> MediaRenderer {
        guard players[id] != nil, let renderer = renderers[id] else { throw SonosAPIError.playerNotFound }
        return renderer
    }

    private func update(_ id: String, _ change: (inout SonosPlayer) -> Void) throws -> SonosPlayer {
        guard var player = players[id] else { throw SonosAPIError.playerNotFound }
        change(&player)
        players[id] = player
        return player
    }

    private func visibleRooms(from devices: [UPnPDevice]) async throws -> [Room] {
        for device in devices {
            try Task.checkCancellation()
            guard let topology = SonosLocalDiscovery.service(ofType: SonosLocalDiscovery.topologyService, on: device),
                  let response = try? await soap.invoke("GetZoneGroupState", on: topology),
                  let xml = response["ZoneGroupState"],
                  let rooms = try? Self.rooms(from: xml), !rooms.isEmpty else { continue }
            return rooms
        }
        throw SonosAPIError.playerNotFound
    }

    static func rooms(from xml: String) throws -> [Room] {
        let document = try XMLDocument(xmlString: xml, options: .nodeLoadExternalEntitiesNever)
        let members = try document.nodes(forXPath: "//ZoneGroup/ZoneGroupMember")
        var rooms: [String: Room] = [:]
        for member in members.compactMap({ $0 as? XMLElement }) {
            guard member.attribute(forName: "Invisible")?.stringValue != "1",
                  let id = member.attribute(forName: "UUID")?.stringValue?.uppercased(), id.hasPrefix("RINCON_"),
                  let name = member.attribute(forName: "ZoneName")?.stringValue, !name.isEmpty else { continue }
            let coordinatorID = (member.parent as? XMLElement)?.attribute(forName: "Coordinator")?.stringValue?.uppercased()
            rooms[id] = Room(id: id, name: name, coordinatorID: coordinatorID)
        }
        return rooms.values.sorted { $0.id < $1.id }
    }

    private func makePlayer(room: Room, renderer: MediaRenderer, sourceRenderer: MediaRenderer) async throws -> SonosPlayer {
        async let volume = renderer.volume()
        async let muted = renderer.isMuted()
        async let source = playbackSource(on: sourceRenderer)
        async let dialog = readEQ("DialogLevel", on: renderer)
        async let night = readEQ("NightMode", on: renderer)
        let (dialogValue, nightValue) = await (dialog, night)
        return try await SonosPlayer(
            id: room.id,
            groupID: room.coordinatorID,
            roomName: room.name,
            deviceName: renderer.device.modelName ?? "Sonos",
            playbackSource: source,
            volume: volume,
            muted: muted,
            enhanceDialog: dialogValue ?? false,
            nightMode: nightValue ?? false,
            supportsEnhanceDialog: dialogValue != nil,
            supportsNightMode: nightValue != nil
        )
    }

    private func playbackSource(on renderer: MediaRenderer) async -> String? {
        guard let position = try? await renderer.positionInfo() else { return nil }
        let uri = position.trackURI?.lowercased() ?? ""
        if uri.hasPrefix("spotify:") || uri.hasPrefix("x-sonos-spotify:") { return "Spotify" }
        if uri.hasPrefix("x-sonos-htastream:") { return "TV" }
        if uri.hasPrefix("x-rincon-stream:") { return "Line-In" }
        return nil
    }

    private func readEQ(_ type: String, on renderer: MediaRenderer) async -> Bool? {
        guard let rendering = renderer.renderingControl,
              let response = try? await soap.invoke("GetEQ", on: rendering, arguments: ["InstanceID": "0", "EQType": type]),
              let value = response["CurrentValue"]?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if let number = Int(value) { return number != 0 }
        return Bool(value.lowercased())
    }

    private func writeEQ(_ type: String, enabled: Bool, playerID: String) async throws {
        guard let rendering = try renderer(for: playerID).renderingControl else {
            throw SonosAPIError.playerNotFound
        }
        revisions[playerID, default: 0] += 1
        defer { revisions[playerID, default: 0] += 1 }
        _ = try await soap.invoke(
            "SetEQ", on: rendering,
            arguments: ["InstanceID": "0", "EQType": type, "DesiredValue": enabled ? "1" : "0"]
        )
    }
}
