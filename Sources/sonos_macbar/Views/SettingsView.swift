import SwiftUI

struct SettingsView: View {
    @Bindable var state: SonosState
    let language: AppLanguage
    @Binding var appLanguageRawValue: String
    @Binding var connectionMode: SonosConnectionMode
    let closeAction: () -> Void

    @State private var isConfirmingDisconnect = false
    @State private var isDisconnecting = false
    @State private var showsControlModeInfo = false

    var body: some View {
        VStack(spacing: 10) {
            PanelHeader(title: language.settingsTitle, closeLabel: language.close, onClose: closeAction)

            PanelCard {
                VStack(spacing: 0) {
                    connectionRow.padding(10)

                    if !state.players.isEmpty || (state.isConnected && !state.isLoading) {
                        rowDivider
                        roomRow.padding(10)
                    }

                    if isConfirmingDisconnect && canDisconnect {
                        rowDivider
                        disconnectConfirmation.padding(10)
                    }
                }
            }

            PanelCard {
                VStack(spacing: 0) {
                    languageRow.padding(10)
                    rowDivider
                    AppUpdateView(language: language).padding(10)
                    rowDivider
                    connectionModeFooter
                }
            }
        }
        .onChange(of: connectionMode) { _, _ in
            isConfirmingDisconnect = false
        }
    }

    private var connectionRow: some View {
        HStack(spacing: 8) {
            PanelIcon("hifispeaker.2.fill", tint: .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sonos")
                    .font(.callout.weight(.semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(state.isConnected && !state.isLoading && state.errorMessage == nil ? Color.green : Color.secondary)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text(connectionLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(connectionHelp)
                }
            }

            Spacer(minLength: 4)

            if isDisconnecting || state.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24)
                    .accessibilityLabel(language.loading)
            } else if state.authState == .openingBrowser || state.authState == .waitingForAuthorization {
                iconButton(language.reopenBrowser, symbol: "safari", action: state.reopenSonosLogin)
                iconButton(language.cancel, symbol: "xmark", action: state.cancelSonosLogin)
            } else {
                if state.canConnectSonos {
                    if canDisconnect {
                        iconButton(language.connectSonos, symbol: "link", action: state.connectSonos)
                    } else {
                        Button(action: state.connectSonos) {
                            Label(language.connectSonos, systemImage: "link")
                        }
                    }
                } else if state.connectionMode == .local || canDisconnect || state.authState == .sessionUnavailable {
                    iconButton(language.reloadRooms, symbol: "arrow.clockwise") {
                        Task { await state.loadPlayers() }
                    }
                    .disabled(state.isWaitingForRateLimit)
                }
                if canDisconnect {
                    iconButton(language.disconnectConnection, symbol: "rectangle.portrait.and.arrow.right") {
                        isConfirmingDisconnect.toggle()
                    }
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var connectionModeFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(language.controlMode)
                    .foregroundStyle(.secondary)

                Button {
                    showsControlModeInfo.toggle()
                } label: {
                    Image(systemName: showsControlModeInfo ? "info.circle.fill" : "info.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.controlModeInfo)
                .accessibilityAddTraits(showsControlModeInfo ? .isSelected : [])
                .help(language.controlModeInfo)

                Spacer()

                Picker(language.controlMode, selection: $connectionMode) {
                    Text(language.localMode).tag(SonosConnectionMode.local)
                    Text("Cloud").tag(SonosConnectionMode.cloud)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            if showsControlModeInfo {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Text(language.localMode).bold()) · \(language.localModeHelp)")
                    Text("\(Text("Cloud").bold()) · \(language.cloudModeHelp)")
                }
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            }
        }
        .font(.caption)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var roomRow: some View {
        HStack(spacing: 8) {
            PanelIcon("house.fill", tint: .secondary)
            Text(language.room)
            Spacer()

            if state.players.isEmpty {
                Text(language.noRoom)
                    .foregroundStyle(.secondary)
            } else {
                Picker(language.room, selection: $state.selectedPlayerID) {
                    ForEach(state.players) { player in
                        Text(player.roomName).tag(Optional(player.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 175, alignment: .trailing)
            }
        }
        .font(.callout)
        .controlSize(.small)
    }

    private var languageRow: some View {
        HStack(spacing: 8) {
            PanelIcon("globe", tint: .indigo)
            Text(language.language)
            Spacer()
            Picker(language.language, selection: $appLanguageRawValue) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .font(.callout)
        .controlSize(.small)
    }

    private var disconnectConfirmation: some View {
        HStack(spacing: 8) {
            Text(language.disconnectSonosQuestion)
            Spacer()
            Button(language.cancel) {
                isConfirmingDisconnect = false
            }
            Button(language.disconnect, role: .destructive) {
                isConfirmingDisconnect = false
                isDisconnecting = true
                Task {
                    await state.disconnectSonos()
                    isDisconnecting = false
                }
            }
        }
        .font(.callout)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var canDisconnect: Bool {
        state.connectionMode == .cloud && (state.isConnected || !state.players.isEmpty)
    }

    private var connectionLabel: String {
        switch state.authState {
        case .connected, .sessionUnavailable:
            state.connectionStatus(for: language)
        case .disconnected:
            language.notConnected
        case .checking, .refreshing:
            language.loading
        case .openingBrowser, .waitingForAuthorization:
            language.browserLogin
        case .notConfigured, .failed:
            language.connectionTitle(for: state.authState)
        }
    }

    private var connectionHelp: String {
        if let issue = state.connectionIssue { return language.connectionIssueMessage(for: issue) }
        if state.connectionMode == .local { return language.localNetworkHelp }
        return state.errorMessage ?? state.authState.userMessage(for: language)
    }

    private var rowDivider: some View {
        Divider().padding(.horizontal, 10)
    }

    private func iconButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(minWidth: 16)
        }
        .help(title)
    }
}
