import SwiftUI

struct ControlPanelView: View {
    let cloudState: SonosState
    let localState: SonosState
    @AppStorage("sonosConnectionMode") private var connectionMode = SonosConnectionMode.cloud
    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.english.rawValue
    @State private var page: Page = .controls

    private enum Page {
        case controls, equalizer, settings
    }

    private struct PollingTarget: Equatable {
        let mode: SonosConnectionMode
        let playerID: SonosPlayer.ID?
    }

    private var state: SonosState {
        connectionMode == .local ? localState : cloudState
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .english
    }

    var body: some View {
        Group {
            if page == .settings {
                SettingsView(
                    state: state,
                    language: appLanguage,
                    appLanguageRawValue: $appLanguageRawValue,
                    connectionMode: $connectionMode
                ) {
                    page = .controls
                }
            } else if page == .equalizer, let player = state.selectedPlayer {
                EqualizerView(player: player, language: appLanguage) {
                    page = .controls
                }
                .id(player.id)
            } else {
                VStack(spacing: 10) {
                    if let player = state.selectedPlayer, !state.isAuthenticationRequired {
                        PanelCard {
                            PlayerHeaderView(
                                state: state,
                                player: player,
                                language: appLanguage,
                                equalizerAction: { page = .equalizer }
                            ) {
                                page = .settings
                            }
                            .padding(10)
                        }

                        PanelCard {
                            VStack(spacing: 9) {
                                VolumeControlView(state: state, player: player, language: appLanguage)
                                if player.supportsEnhanceDialog || player.supportsNightMode {
                                    Divider()
                                    HomeTheaterControlsView(state: state, player: player, language: appLanguage)
                                }
                            }
                            .padding(10)
                        }
                    } else if state.showsConnectionView {
                        PanelCard {
                            SonosConnectionView(state: state, language: appLanguage) {
                                page = .settings
                            }
                            .padding(10)
                        }
                    } else {
                        if state.isLoading {
                            ProgressView()
                                .frame(height: 180)
                        } else {
                            ContentUnavailableView(appLanguage.noRoom, systemImage: "hifispeaker.2")
                                .frame(height: 180)
                        }
                    }

                    if let issue = state.connectionIssue, state.selectedPlayer != nil {
                        Label(appLanguage.connectionIssueMessage(for: issue), systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    } else if let errorMessage = state.errorMessage, state.rateLimitedUntil == nil, connectionMode == .cloud {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .background {
            if state.isPopoverOpen {
                Color.clear.task(id: PollingTarget(mode: connectionMode, playerID: state.selectedPlayerID)) { [state] in
                    await state.pollSelectedPlayerState()
                }
            }
        }
        .onChange(of: connectionMode) { previous, _ in
            let previousState = previous == .local ? localState : cloudState
            previousState.cancelPendingVolumeUpdate()
            if state.selectedPlayerID == nil { state.selectedPlayerID = previousState.selectedPlayerID }
            if page == .equalizer { page = .controls }
        }
        .onChange(of: state.selectedPlayer?.id) { _, id in
            if id == nil, page == .equalizer { page = .controls }
        }
    }
}

private struct SonosConnectionView: View {
    @Bindable var state: SonosState
    let language: AppLanguage
    let settingsAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PanelIcon(iconName, tint: .blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                PanelIconButton(title: language.settingsTitle, symbol: "gearshape", action: settingsAction)
            }

            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            switch connectionState {
            case .openingBrowser, .waitingForAuthorization:
                Button {
                    state.reopenSonosLogin()
                } label: {
                    Label(language.reopenBrowser, systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(role: .cancel) {
                    state.cancelSonosLogin()
                } label: {
                    Label(language.cancel, systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)

            case .sessionUnavailable, .connected, .failed:
                Button {
                    if case .failed = connectionState {
                        state.connectSonos()
                    } else {
                        Task { await state.loadPlayers() }
                    }
                } label: {
                    Label(language.retry, systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(state.isLoading || state.isWaitingForRateLimit)

            case .notConfigured, .checking, .refreshing:
                EmptyView()

            default:
                Button {
                    state.connectSonos()
                } label: {
                    Label(language.connectToSonos, systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    private var title: String {
        if state.connectionMode == .local {
            return state.isLoading ? language.searchingLocalRooms : language.connectionIssueTitle(for: .localRequestFailed)
        }
        if let issue = state.connectionIssue { return language.connectionIssueTitle(for: issue) }
        return language.connectionTitle(for: connectionState)
    }

    private var message: String {
        if state.connectionMode == .local { return language.localNetworkHelp }
        if let issue = state.connectionIssue { return language.connectionIssueMessage(for: issue) }
        return language.connectionMessage(for: connectionState)
    }

    private var connectionState: SonosAuthState {
        if state.authState == .connected, state.isAuthenticationRequired { return .disconnected }
        return state.authState
    }

    private var iconName: String {
        switch connectionState {
        case .sessionUnavailable, .connected, .failed:
            "wifi.exclamationmark"
        case .openingBrowser, .waitingForAuthorization:
            "safari.fill"
        default:
            "link.circle.fill"
        }
    }

    private var showsProgress: Bool {
        if state.connectionMode == .local { return state.isLoading }
        return switch connectionState {
        case .checking, .openingBrowser, .waitingForAuthorization, .refreshing:
            true
        default:
            false
        }
    }
}

struct PanelHeader: View {
    let title: String
    let closeLabel: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(closeLabel)
        }
    }
}

#Preview {
    let cloud = SonosState(service: MockSonosService())
    let local = SonosState(service: MockSonosService(), connectionMode: .local)
    ControlPanelView(cloudState: cloud, localState: local)
        .frame(width: 340)
        .task {
            cloud.isPopoverOpen = true
            local.isPopoverOpen = true
        }
}
