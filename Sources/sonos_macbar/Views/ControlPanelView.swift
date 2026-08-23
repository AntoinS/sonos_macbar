import SwiftUI

struct ControlPanelView: View {
    @Bindable var state: SonosState
    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.english.rawValue
    @State private var isShowingSettings = false

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .english
    }

    var body: some View {
        Group {
            if isShowingSettings {
                EmbeddedSettingsView(state: state, language: appLanguage, appLanguageRawValue: $appLanguageRawValue) {
                    isShowingSettings = false
                }
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
                            language: appLanguage
                        ) {
                            isShowingSettings = true
                        }

                        VolumeControlView(state: state, player: player, language: appLanguage)

                        HomeTheaterControlsView(state: state, player: player, language: appLanguage)
                    } else if state.showsConnectionView {
                        SonosConnectionView(state: state, language: appLanguage) {
                            isShowingSettings = true
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

private struct EmbeddedSettingsView: View {
    @Bindable var state: SonosState
    let language: AppLanguage
    @Binding var appLanguageRawValue: String
    let closeAction: () -> Void

    @State private var snapshot: SonosAccountSnapshot?
    @State private var isConfirmingDisconnect = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(language.settingsTitle)
                    .font(.headline)

                Spacer()

                Button(action: closeAction) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(language.close)
            }

            VStack(spacing: 9) {
                SettingsInfoRow(title: language.status, value: snapshot?.connectionStatus ?? state.connectionStatus(for: language))
                SettingsInfoRow(title: language.login, value: snapshot?.authStatus ?? state.authState.userMessage(for: language))
                roomPicker
                SettingsInfoRow(title: language.session, value: snapshot?.hasBrokerSession == true ? language.stored : language.notStored)
                SettingsInfoRow(title: language.token, value: snapshot?.hasAccessToken == true ? language.stored : language.notStored)
                languagePicker
            }
            .padding(.vertical, 2)

            Divider()

            VStack(spacing: 8) {
                Button {
                    Task {
                        await state.reloadPlayers()
                        await refreshSnapshot()
                    }
                } label: {
                    Label(state.isLoading ? language.loading : language.reloadRooms, systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .disabled(state.isLoading)

                if state.canConnectSonos {
                    Button {
                        state.connectSonos()
                    } label: {
                        Label(language.connectSonos, systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                }

                if isConfirmingDisconnect {
                    HStack(spacing: 8) {
                        Button(language.cancel) {
                            isConfirmingDisconnect = false
                        }
                        .frame(maxWidth: .infinity)

                        Button(language.disconnect, role: .destructive) {
                            Task {
                                await state.disconnectSonos()
                                isConfirmingDisconnect = false
                                await refreshSnapshot()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else if snapshot?.hasAccessToken == true || snapshot?.hasBrokerSession == true || !state.players.isEmpty {
                    Button(role: .destructive) {
                        isConfirmingDisconnect = true
                    } label: {
                        Label(language.disconnectConnection, systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await refreshSnapshot()
        }
        .onChange(of: appLanguageRawValue) {
            Task {
                await refreshSnapshot()
            }
        }
    }

    @ViewBuilder
    private var roomPicker: some View {
        if state.players.isEmpty {
            SettingsInfoRow(title: language.room, value: language.none)
        } else {
            HStack(spacing: 12) {
                Text(language.room)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker(language.room, selection: $state.selectedPlayerID) {
                    ForEach(state.players) { player in
                        Text(player.roomName)
                            .tag(Optional(player.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 190, alignment: .trailing)
            }
            .font(.callout)
        }
    }

    private var languagePicker: some View {
        HStack(spacing: 12) {
            Text(language.language)
                .foregroundStyle(.secondary)
            Spacer()
            Picker(language.language, selection: $appLanguageRawValue) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName)
                        .tag(language.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 190, alignment: .trailing)
        }
        .font(.callout)
    }

    private func refreshSnapshot() async {
        snapshot = await state.accountSnapshot(language: language)
    }
}

private struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
        }
        .font(.callout)
    }
}

#Preview {
    ControlPanelView(state: SonosState(service: MockSonosService()))
        .frame(width: 340)
}
