import SwiftUI

struct PlayerHeaderView: View {
    @Bindable var state: SonosState
    let player: SonosPlayer
    let language: AppLanguage
    let equalizerAction: () -> Void
    let settingsAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            PanelIcon("hifispeaker.2.fill", tint: .blue)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    roomTitle
                    Circle()
                        .fill(state.isConnected && !state.isLoading && state.errorMessage == nil ? Color.green : Color.secondary)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                }
                .font(.callout.weight(.semibold))
                .help(connectionStatus)

                Text(deviceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            PanelIconButton(title: "Equalizer", symbol: "slider.horizontal.3", action: equalizerAction)
            PanelIconButton(title: language.settingsTitle, symbol: "gearshape", action: settingsAction)
        }
    }

    @ViewBuilder
    private var roomTitle: some View {
        if state.players.count > 1 {
            Menu {
                Picker(language.room, selection: $state.selectedPlayerID) {
                    ForEach(state.players) { room in
                        Text(room.roomName).tag(Optional(room.id))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Text(player.roomName).lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(language.room)
            .accessibilityValue("\(player.roomName), \(connectionStatus)")
        } else {
            Text(player.roomName)
                .lineLimit(1)
                .accessibilityValue(connectionStatus)
        }
    }

    private var connectionStatus: String {
        state.connectionStatus(for: language)
    }

    private var deviceSummary: String {
        guard let source = player.playbackSource, !source.isEmpty else { return player.deviceName }
        return "\(player.deviceName) · \(source)"
    }
}

#Preview {
    PlayerHeaderView(
        state: SonosState(service: MockSonosService()),
        player: .mockArc,
        language: .english,
        equalizerAction: {}
    ) {}
    .padding()
    .frame(width: 340)
}
