import Foundation
import Observation

@MainActor
@Observable
final class SonosState {
    private let service: any SonosAPI
    private let tokenStore: SonosTokenStore
    private let oauthCoordinator: SonosOAuthCoordinator?
    private var liveVolumeTask: Task<Void, Never>?

    private(set) var players: [SonosPlayer] = []
    var selectedPlayerID: SonosPlayer.ID?
    private(set) var isLoading = false
    private(set) var isAuthenticationRequired = false
    private(set) var errorMessage: String?

    var authState: SonosAuthState {
        oauthCoordinator?.authState ?? (isAuthenticationRequired ? .disconnected : .connected)
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
        case .disconnected, .failed, .offline, .notConfigured:
            true
        case .checking, .openingBrowser, .waitingForAuthorization, .connected, .refreshing:
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

    func start() async {
        await oauthCoordinator?.prepareAtLaunch()

        switch authState {
        case .connected:
            await loadPlayers()
        case .checking, .notConfigured, .disconnected, .openingBrowser, .waitingForAuthorization, .refreshing, .failed, .offline:
            break
        }
    }

    func loadPlayers() async {
        isLoading = true
        errorMessage = nil

        do {
            players = try await service.fetchPlayers()
            isAuthenticationRequired = false
            if selectedPlayerID == nil {
                selectedPlayerID = players.first?.id
            }
        } catch {
            updateAuthenticationRequirement(for: error)
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reloadPlayers() async {
        if players.isEmpty, !isAuthenticationRequired {
            await start()
        } else {
            await loadPlayers()
        }
    }

    func connectSonos() {
        errorMessage = nil
        oauthCoordinator?.beginLogin { [weak self] in
            await self?.loadPlayers()
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
            selectedPlayerID = nil
            isAuthenticationRequired = true
            errorMessage = nil
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
            updateAuthenticationRequirement(for: error)
            errorMessage = error.localizedDescription
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
                self.updateAuthenticationRequirement(for: error)
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func pollSelectedPlayerState() async {
        var pollCount = 0

        while !Task.isCancelled {
            if let player = selectedPlayer, !isAuthenticationRequired {
                await refreshPlayerState(player, includingSource: pollCount % 4 == 0)
                pollCount += 1
            }

            do {
                try await Task.sleep(for: .milliseconds(1500))
            } catch {
                break
            }
        }
    }

    func accountSnapshot(language: AppLanguage) async -> SonosAccountSnapshot {
        let isConnected = authState == .connected && !isAuthenticationRequired

        return SonosAccountSnapshot(
            connectionStatus: connectionStatus(for: language),
            authStatus: authState.userMessage(for: language),
            selectedRoomName: selectedPlayer?.roomName,
            hasBrokerSession: isConnected,
            hasAccessToken: isConnected
        )
    }

    func setMuted(_ isMuted: Bool) async {
        guard let player = selectedPlayer else { return }

        updateSelectedPlayer { $0.muted = isMuted }

        do {
            replacePlayer(try await service.setMuted(isMuted, for: player.id))
        } catch {
            updateAuthenticationRequirement(for: error)
            errorMessage = error.localizedDescription
        }
    }

    func setEnhanceDialog(_ isEnabled: Bool) async {
        guard let player = selectedPlayer, player.supportsEnhanceDialog else { return }

        updateSelectedPlayer { $0.enhanceDialog = isEnabled }

        do {
            replacePlayer(try await service.setEnhanceDialog(isEnabled, for: player.id))
        } catch {
            updateAuthenticationRequirement(for: error)
            errorMessage = error.localizedDescription
        }
    }

    func setNightMode(_ isEnabled: Bool) async {
        guard let player = selectedPlayer, player.supportsNightMode else { return }

        updateSelectedPlayer { $0.nightMode = isEnabled }

        do {
            replacePlayer(try await service.setNightMode(isEnabled, for: player.id))
        } catch {
            updateAuthenticationRequirement(for: error)
            errorMessage = error.localizedDescription
        }
    }

    private func updateAuthenticationRequirement(for error: Error) {
        guard let apiError = error as? SonosAPIError else { return }

        switch apiError {
        case .credentialsRequired:
            isAuthenticationRequired = true
        case let .requestFailed(statusCode, _) where statusCode == 401 || statusCode == 403:
            isAuthenticationRequired = true
        default:
            break
        }
    }

    private func refreshPlayerState(_ player: SonosPlayer, includingSource: Bool) async {
        do {
            replacePlayer(try await service.refreshPlayerState(player, includingSource: includingSource))
        } catch {
            guard !Self.isCancellationError(error) else { return }
            updateAuthenticationRequirement(for: error)
            errorMessage = error.localizedDescription
        }
    }

    private func replacePlayer(_ player: SonosPlayer) {
        guard let index = players.firstIndex(where: { $0.id == player.id }) else { return }
        players[index] = player
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

struct SonosAccountSnapshot: Equatable {
    let connectionStatus: String
    let authStatus: String
    let selectedRoomName: String?
    let hasBrokerSession: Bool
    let hasAccessToken: Bool
}
