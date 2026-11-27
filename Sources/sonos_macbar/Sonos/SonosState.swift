import Foundation
import Observation

@MainActor
@Observable
final class SonosState {
    private let service: any SonosAPI
    private let tokenStore: SonosTokenStore
    private let oauthCoordinator: SonosOAuthCoordinator?
    private var liveVolumeTask: Task<Void, Never>?
    private var playersLoadedAt: Date?

    private(set) var players: [SonosPlayer] = []
    var selectedPlayerID: SonosPlayer.ID?
    private(set) var isLoading = false
    private(set) var isAuthenticationRequired = false
    private(set) var errorMessage: String?
    private(set) var rateLimitedUntil: Date?
    var isPopoverOpen = false

    var authState: SonosAuthState {
        oauthCoordinator?.authState ?? (isAuthenticationRequired ? .disconnected : .connected)
    }

    var isConnected: Bool {
        authState == .connected && !isAuthenticationRequired
    }

    var showsConnectionView: Bool {
        switch authState {
        case .checking, .notConfigured, .disconnected, .openingBrowser, .waitingForAuthorization, .refreshing, .offline, .failed:
            true
        case .connected:
            isAuthenticationRequired || (players.isEmpty && errorMessage != nil)
        }
    }

    var selectedPlayer: SonosPlayer? {
        guard let selectedPlayerID else { return players.first }
        return players.first { $0.id == selectedPlayerID }
    }

    func connectionStatus(for language: AppLanguage) -> String {
        language.connectionStatus(
            isLoading: isLoading,
            isAuthenticationRequired: isAuthenticationRequired,
            hasError: errorMessage != nil
        )
    }

    var canConnectSonos: Bool {
        switch authState {
        case .disconnected, .failed, .notConfigured:
            true
        case .connected:
            isAuthenticationRequired
        case .checking, .openingBrowser, .waitingForAuthorization, .refreshing, .offline:
            false
        }
    }

    init(
        service: any SonosAPI,
        tokenStore: SonosTokenStore = SonosTokenStore(),
        oauthCoordinator: SonosOAuthCoordinator? = nil
    ) {
        self.service = service
        self.tokenStore = tokenStore
        self.oauthCoordinator = oauthCoordinator
    }

    func loadPlayers() async {
        guard !isLoading, !Task.isCancelled, !isWaitingForRateLimit else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try await oauthCoordinator?.restoreSession()
            guard authState == .connected else { return }
            let loadedPlayers = try await service.fetchPlayers()
            try Task.checkCancellation()
            players = loadedPlayers
            playersLoadedAt = .now
            isAuthenticationRequired = false
            clearRequestError()
            if !players.contains(where: { $0.id == selectedPlayerID }) {
                selectedPlayerID = players.first?.id
            }
        } catch {
            recordRequestError(error)
        }
    }

    func connectSonos() {
        errorMessage = nil
        oauthCoordinator?.beginLogin { [weak self] in
            guard let self else { return }
            self.isAuthenticationRequired = false
            await self.loadPlayers()
        }
    }

    func reopenSonosLogin() {
        oauthCoordinator?.reopenBrowser()
    }

    func cancelSonosLogin() {
        oauthCoordinator?.cancelLogin()
    }

    func handleOAuthCallback(_ url: URL) {
        oauthCoordinator?.handleCallback(url)
    }

    func disconnectSonos() async {
        do {
            if let oauthCoordinator {
                try await oauthCoordinator.disconnect()
            } else {
                try await tokenStore.deleteAllSonosCredentials()
            }

            players = []
            playersLoadedAt = nil
            selectedPlayerID = nil
            isAuthenticationRequired = true
            errorMessage = nil
            rateLimitedUntil = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func previewVolume(_ volume: Int) {
        updateSelectedPlayer { player in
            player.volume = Self.clampedVolume(volume)
            player.muted = false
        }
    }

    func commitVolume(_ volume: Int) async {
        liveVolumeTask?.cancel()
        guard let playerID = selectedPlayer?.id else { return }

        do {
            let player = try await service.setVolume(Self.clampedVolume(volume), for: playerID)
            replacePlayer(player)
        } catch {
            guard !Self.isCancellationError(error) else { return }
            recordRequestError(error)
        }
    }

    func updateVolumeLive(_ volume: Int) {
        let clampedVolume = Self.clampedVolume(volume)
        previewVolume(clampedVolume)

        guard let playerID = selectedPlayer?.id else { return }

        liveVolumeTask?.cancel()
        liveVolumeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
                guard let self else { return }
                let player = try await self.service.setVolume(clampedVolume, for: playerID)
                try Task.checkCancellation()
                self.replacePlayer(player)
            } catch is CancellationError {
                return
            } catch {
                guard !Self.isCancellationError(error) else { return }
                guard let self else { return }
                self.recordRequestError(error)
            }
        }
    }

    func pollSelectedPlayerState() async {
        guard isPopoverOpen else { return }
        let needsRoomRefresh = playersLoadedAt.map { Date().timeIntervalSince($0) >= 300 } ?? true
        if needsRoomRefresh, !isAuthenticationRequired, errorMessage == nil {
            await loadPlayers()
        }
        var pollCount = 0

        while isPopoverOpen, !Task.isCancelled {
            if !isWaitingForRateLimit, !isLoading {
                if let player = selectedPlayer, isConnected {
                    await refreshPlayerState(player, includingSource: pollCount % 4 == 0)
                    pollCount += 1
                } else if !isAuthenticationRequired, authState == .offline || (authState == .connected && errorMessage != nil) {
                    await loadPlayers()
                }
            }

            do {
                let retryDelay = rateLimitedUntil?.timeIntervalSinceNow ?? 0
                try await Task.sleep(for: .seconds(min(86_400, max(6, retryDelay))))
            } catch {
                break
            }
        }
    }

    func setMuted(_ isMuted: Bool) async {
        guard let player = selectedPlayer else { return }

        updateSelectedPlayer { $0.muted = isMuted }

        do {
            replacePlayer(try await service.setMuted(isMuted, for: player.id))
        } catch {
            recordRequestError(error)
        }
    }

    func setEnhanceDialog(_ isEnabled: Bool) async {
        guard let player = selectedPlayer, player.supportsEnhanceDialog else { return }

        updateSelectedPlayer { $0.enhanceDialog = isEnabled }

        do {
            replacePlayer(try await service.setEnhanceDialog(isEnabled, for: player.id))
        } catch {
            recordRequestError(error)
        }
    }

    func setNightMode(_ isEnabled: Bool) async {
        guard let player = selectedPlayer, player.supportsNightMode else { return }

        updateSelectedPlayer { $0.nightMode = isEnabled }

        do {
            replacePlayer(try await service.setNightMode(isEnabled, for: player.id))
        } catch {
            recordRequestError(error)
        }
    }

    private var isWaitingForRateLimit: Bool {
        rateLimitedUntil.map { $0 > .now } ?? false
    }

    private func recordRequestError(_ error: Error) {
        guard !Self.isCancellationError(error), !Task.isCancelled else { return }
        if case SonosAPIError.credentialsRequired = error {
            isAuthenticationRequired = true
        }
        if let limited = error as? SonosRateLimited {
            rateLimitedUntil = max(rateLimitedUntil ?? .now, limited.retryAt)
        } else {
            if !isWaitingForRateLimit { rateLimitedUntil = nil }
        }
        errorMessage = error.localizedDescription
    }

    private func clearRequestError() {
        guard !isWaitingForRateLimit else { return }
        rateLimitedUntil = nil
        errorMessage = nil
    }

    private func refreshPlayerState(_ player: SonosPlayer, includingSource: Bool) async {
        do {
            replacePlayer(try await service.refreshPlayerState(player, includingSource: includingSource))
        } catch {
            guard !Self.isCancellationError(error) else { return }
            recordRequestError(error)
        }
    }

    private func replacePlayer(_ player: SonosPlayer) {
        guard let index = players.firstIndex(where: { $0.id == player.id }) else { return }
        players[index] = player
        clearRequestError()
    }

    private func updateSelectedPlayer(_ update: (inout SonosPlayer) -> Void) {
        guard let player = selectedPlayer,
              let index = players.firstIndex(where: { $0.id == player.id }) else { return }

        update(&players[index])
    }

    private static func clampedVolume(_ volume: Int) -> Int {
        min(100, max(0, volume))
    }

    private static func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        return (error as? URLError)?.code == .cancelled
    }
}
