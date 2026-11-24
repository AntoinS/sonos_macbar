import SwiftUI

struct VolumeControlView: View {
    let state: SonosState
    let player: SonosPlayer
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Task { await state.setMuted(!player.muted) }
            } label: {
                PanelIcon(speakerImage, tint: .secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.muted ? language.unmute : language.mute)
            .help(player.muted ? language.unmute : language.mute)

            AudioSlider(
                title: language.volume,
                value: player.volume,
                range: 0...100,
                isDimmed: player.muted,
                displayValue: { player.muted ? language.off : String($0) },
                spokenValue: { language.volumeValue(isMuted: player.muted, volume: $0) },
                onPreview: { state.updateVolumeLive($0) }
            ) { value in
                Task { await state.commitVolume(value) }
            }
        }
    }

    private var speakerImage: String {
        if player.muted {
            return "speaker.slash.fill"
        }

        switch player.volume {
        case 0:
            return "speaker.slash.fill"
        case 1..<45:
            return "speaker.wave.1.fill"
        case 45..<75:
            return "speaker.wave.2.fill"
        default:
            return "speaker.wave.3.fill"
        }
    }
}

#Preview {
    VolumeControlView(state: SonosState(service: MockSonosService()), player: .mockArc, language: .english)
        .padding()
        .frame(width: 340)
}
