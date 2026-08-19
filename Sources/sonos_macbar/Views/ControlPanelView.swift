import SwiftUI

struct ControlPanelView: View {
    @Bindable var state: SonosState
    @State private var isShowingSettings = false

    var body: some View {
        Group {
            if isShowingSettings {
                EmbeddedSettingsView(state: state) {
                    isShowingSettings = false
                }
            } else {
                VStack(spacing: 10) {
                    if state.players.count > 1 {
                        Picker("Room", selection: $state.selectedPlayerID) {
                            ForEach(state.players) { player in
                                Text(player.roomName)
                                    .tag(Optional(player.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    if let player = state.selectedPlayer {
                        PlayerHeaderView(player: player, connectionStatus: state.connectionStatus) {
                            isShowingSettings = true
                        }

                        VolumeControlView(state: state, player: player)

                        HomeTheaterControlsView(state: state, player: player)
                    } else if state.showsConnectionView {
                        SonosConnectionView(state: state) {
                            isShowingSettings = true
                        }
                    } else {
                        if state.isLoading {
                            ProgressView()
                                .frame(height: 180)
                        } else {
                            ContentUnavailableView("Kein Raum", systemImage: "hifispeaker.2")
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
    }
}

private struct SonosConnectionView: View {
    @Bindable var state: SonosState
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
                .accessibilityLabel("Einstellungen")
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
                    Label("Browser erneut öffnen", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(role: .cancel) {
                    state.cancelSonosLogin()
                } label: {
                    Label("Abbrechen", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)

            case .offline, .failed:
                Button {
                    Task { await state.loadPlayers() }
                } label: {
                    Label("Erneut versuchen", systemImage: "arrow.clockwise")
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
                    Label("Mit Sonos verbinden", systemImage: "link")
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
        switch state.authState {
        case .checking:
            "Sonos-Verbindung prüfen"
        case .notConfigured:
            "Sonos-Anmeldung wird eingerichtet"
        case .openingBrowser, .waitingForAuthorization:
            "Anmeldung im Browser abschließen"
        case .offline:
            "Sonos ist gerade nicht erreichbar"
        case .failed:
            "Sonos konnte nicht verbunden werden"
        default:
            "Sonos ist nicht verbunden"
        }
    }

    private var message: String {
        switch state.authState {
        case .notConfigured:
            "Die Sonos-Anmeldung ist serverseitig noch nicht verfügbar."
        case .openingBrowser, .waitingForAuthorization:
            "Melde dich bei Sonos an und erlaube den Zugriff."
        case .offline:
            "Die Verbindung wird automatisch erneut versucht."
        case let .failed(message):
            message
        default:
            "Verbinde dein Sonos-Konto, um Räume und Wiedergabe zu steuern."
        }
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
    let closeAction: () -> Void

    @State private var snapshot: SonosAccountSnapshot?
    @State private var isConfirmingDisconnect = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Einstellungen")
                    .font(.headline)

                Spacer()

                Button(action: closeAction) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Schliessen")
            }

            VStack(spacing: 9) {
                SettingsInfoRow(title: "Status", value: snapshot?.connectionStatus ?? state.connectionStatus)
                SettingsInfoRow(title: "Anmeldung", value: snapshot?.authStatus ?? state.authState.userMessage)
                roomPicker
                SettingsInfoRow(title: "Sitzung", value: snapshot?.hasBrokerSession == true ? "Gespeichert" : "Nicht gespeichert")
                SettingsInfoRow(title: "Token", value: snapshot?.hasAccessToken == true ? "Gespeichert" : "Nicht gespeichert")
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
                    Label(state.isLoading ? "Lädt" : "Räume neu laden", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .disabled(state.isLoading)

                if state.canConnectSonos {
                    Button {
                        state.connectSonos()
                    } label: {
                        Label("Sonos verbinden", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                }

                if isConfirmingDisconnect {
                    HStack(spacing: 8) {
                        Button("Abbrechen") {
                            isConfirmingDisconnect = false
                        }
                        .frame(maxWidth: .infinity)

                        Button("Trennen", role: .destructive) {
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
                        Label("Verbindung trennen", systemImage: "rectangle.portrait.and.arrow.right")
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
    }

    @ViewBuilder
    private var roomPicker: some View {
        if state.players.isEmpty {
            SettingsInfoRow(title: "Raum", value: "Keiner")
        } else {
            HStack(spacing: 12) {
                Text("Raum")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Raum", selection: $state.selectedPlayerID) {
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

    private func refreshSnapshot() async {
        snapshot = await state.accountSnapshot()
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
