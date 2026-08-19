import Foundation

actor MockSonosService: SonosAPI {
    private var players: [SonosPlayer]

    init(players: [SonosPlayer] = [.mockArc]) {
        self.players = players
    }

    func fetchPlayers() async throws -> [SonosPlayer] {
        try await Task.sleep(for: .milliseconds(120))
        return players
    }

    func setVolume(_ volume: Int, for playerID: SonosPlayer.ID) async throws -> SonosPlayer {
        try await update(playerID: playerID) { player in
            player.volume = min(100, max(0, volume))
            player.muted = false
        }
    }

    func setMuted(_ isMuted: Bool, for playerID: SonosPlayer.ID) async throws -> SonosPlayer {
        try await update(playerID: playerID) { player in
            player.muted = isMuted
        }
    }

    func setEnhanceDialog(_ isEnabled: Bool, for playerID: SonosPlayer.ID) async throws -> SonosPlayer {
        try await update(playerID: playerID) { player in
            guard player.supportsEnhanceDialog else { return }
            player.enhanceDialog = isEnabled
        }
    }

    func setNightMode(_ isEnabled: Bool, for playerID: SonosPlayer.ID) async throws -> SonosPlayer {
        try await update(playerID: playerID) { player in
            guard player.supportsNightMode else { return }
            player.nightMode = isEnabled
        }
    }

    private func update(
        playerID: SonosPlayer.ID,
        mutation: (inout SonosPlayer) -> Void
    ) async throws -> SonosPlayer {
        try await Task.sleep(for: .milliseconds(80))

        guard let index = players.firstIndex(where: { $0.id == playerID }) else {
            throw SonosAPIError.playerNotFound
        }

        mutation(&players[index])
        return players[index]
    }
}
