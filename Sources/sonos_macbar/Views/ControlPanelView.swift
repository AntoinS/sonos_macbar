import SwiftUI

struct ControlPanelView: View {
    @Bindable var state: SonosState
    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.english.rawValue
    @State private var page: Page = .controls

    private enum Page {
        case controls, equalizer, settings
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .english
    }

    var body: some View {
        Group {
            if page == .settings {
                SettingsView(state: state, language: appLanguage, appLanguageRawValue: $appLanguageRawValue) {
                    page = .controls
                }
            } else if page == .equalizer, let player = state.selectedPlayer {
                EqualizerView(player: player, language: appLanguage) {
                    page = .controls
                }
                .id(player.id)
            } else {
                VStack(spacing: 10) {
                    if state.players.count > 1 {
                        Picker(appLanguage.room, selection: $state.selectedPlayerID) {
                            ForEach(state.players) { player in
                                Text(player.roomName)
                                    .tag(Optional(player.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    if let player = state.selectedPlayer {
                        PlayerHeaderView(
                            player: player,
                            connectionStatus: state.connectionStatus(for: appLanguage),
                            language: appLanguage,
                            equalizerAction: { page = .equalizer }
                        ) {
                            page = .settings
                        }

                        VolumeControlView(state: state, player: player, language: appLanguage)

                        HomeTheaterControlsView(state: state, player: player, language: appLanguage)
                    } else if state.showsConnectionView {
                        SonosConnectionView(state: state, language: appLanguage) {
                            page = .settings
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

                    if let errorMessage = state.errorMessage {
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
        .task {
            await state.start()
        }
        .task(id: state.selectedPlayerID) {
            await state.pollSelectedPlayerState()
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
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 36, height: 36)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button(action: settingsAction) {
                    Image(systemName: "gearshape")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(language.settingsTitle)
            }

            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            switch state.authState {
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

            case .offline, .failed:
                Button {
                    Task { await state.loadPlayers() }
                } label: {
                    Label(language.retry, systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

            case .notConfigured:
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
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private var title: String {
        language.connectionTitle(for: state.authState)
    }

    private var message: String {
        language.connectionMessage(for: state.authState)
    }

    private var iconName: String {
        switch state.authState {
        case .offline, .failed:
            "wifi.exclamationmark"
        case .openingBrowser, .waitingForAuthorization:
            "safari.fill"
        default:
            "link.circle.fill"
        }
    }

    private var showsProgress: Bool {
        switch state.authState {
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
    ControlPanelView(state: SonosState(service: MockSonosService()))
        .frame(width: 340)
}
