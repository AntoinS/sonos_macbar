import SwiftUI

struct PlayerHeaderView: View {
    let player: SonosPlayer
    let connectionStatus: String
    let language: AppLanguage
    let equalizerAction: () -> Void
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

                if let playbackSource = player.playbackSource, !playbackSource.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .imageScale(.small)
                            .accessibilityLabel(language.source)

                        Text(playbackSource)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text(connectionStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.16), in: Capsule())

            HStack(spacing: 2) {
                headerButton("Equalizer", icon: "slider.horizontal.3", action: equalizerAction)
                headerButton(language.settingsTitle, icon: "gearshape", action: settingsAction)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private func headerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(title)
        .help(title)
    }
}

#Preview {
    PlayerHeaderView(player: .mockArc, connectionStatus: "Mock Mode", language: .english, equalizerAction: {}) {}
        .padding()
        .frame(width: 340)
}
