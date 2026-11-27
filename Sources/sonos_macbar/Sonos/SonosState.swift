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
    private var polling = SonosPollingSchedule()

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

    var connectionIssue: SonosConnectionIssue? {
        guard !isAuthenticationRequired, authState == .connected || authState == .sessionUnavailable else {
            return nil
        }
        if let rateLimitedUntil { return .rateLimited(retryAt: rateLimitedUntil) }
        if authState == .sessionUnavailable { return .sessionUnavailable }
        return errorMessage == nil ? nil : .cloudRequestFailed
    }

    var showsConnectionView: Bool {
        switch authState {
        case .checking, .notConfigured, .disconnected, .openingBrowser, .waitingForAuthorization, .refreshing, .sessionUnavailable, .failed:
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
        if let connectionIssue { return language.connectionIssueTitle(for: connectionIssue) }
        return language.connectionStatus(
            isLoading: isLoading,
            isAuthenticationRequired: isAuthenticationRequired
        )
    }

    var canConnectSonos: Bool {
        switch authState {
        case .disconnected, .failed, .notConfigured:
            true
        case .connected:
            isAuthenticationRequired
        case .checking, .openingBrowser, .waitingForAuthorization, .refreshing, .sessionUnavailable:
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
        polling.beginRoomRefresh(at: .now)

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
            polling = SonosPollingSchedule()
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
                try await Task.sleep(for: .milliseconds(350))
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
        var needsRoomRefresh = playersLoadedAt.map { Date().timeIntervalSince($0) >= 300 } ?? true

        while isPopoverOpen, !Task.isCancelled {
            if !isWaitingForRateLimit, !isLoading, polling.timeUntilNextRead(at: .now) == .zero {
                if !isAuthenticationRequired,
                   (needsRoomRefresh && errorMessage == nil) || (selectedPlayer == nil && connectionIssue != nil) {
                    needsRoomRefresh = false
                    await loadPlayers()
                } else if let player = selectedPlayer, isConnected {
                    let includeSource = polling.beginPlayerRefresh(at: .now)
                    await refreshPlayerState(player, includingSource: includeSource)
                }
            }

            do {
                let retryDelay = rateLimitedUntil?.timeIntervalSinceNow ?? 0
                let pollDelay = polling.timeUntilNextRead(at: .now)
                let wait = pollDelay > .zero ? pollDelay : SonosPollingSchedule.volumeInterval
                try await Task.sleep(for: max(wait, .seconds(min(86_400, max(0, retryDelay)))))
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

    var isWaitingForRateLimit: Bool {
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

struct SonosPollingSchedule {
    static let volumeInterval: Duration = .seconds(15)
    static let sourceInterval: Duration = .seconds(60)

    private var nextRead: ContinuousClock.Instant?
    private var nextSourceRead: ContinuousClock.Instant?

    func timeUntilNextRead(at now: ContinuousClock.Instant) -> Duration {
        max(.zero, now.duration(to: nextRead ?? now))
    }

    mutating func beginRoomRefresh(at now: ContinuousClock.Instant) {
        nextRead = now.advanced(by: Self.volumeInterval)
        nextSourceRead = now.advanced(by: Self.sourceInterval)
    }

    mutating func beginPlayerRefresh(at now: ContinuousClock.Instant) -> Bool {
        nextRead = now.advanced(by: Self.volumeInterval)
        guard nextSourceRead.map({ now >= $0 }) ?? true else { return false }
        nextSourceRead = now.advanced(by: Self.sourceInterval)
        return true
    }
}
