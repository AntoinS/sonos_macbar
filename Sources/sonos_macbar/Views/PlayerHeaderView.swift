import SwiftUI

struct PlayerHeaderView: View {
    let player: SonosPlayer
    let connectionStatus: String
    let settingsAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hifispeaker.2.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.roomName)
                    .font(.headline)
                    .lineLimit(1)

                Text(player.deviceName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(connectionStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.16), in: Capsule())

            Button(action: settingsAction) {
                Image(systemName: "gearshape")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Einstellungen")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }
}

#Preview {
    PlayerHeaderView(player: .mockArc, connectionStatus: "Mock Mode") {}
        .padding()
        .frame(width: 340)
}
