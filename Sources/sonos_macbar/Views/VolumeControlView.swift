import SwiftUI

struct VolumeControlView: View {
    let state: SonosState
    let player: SonosPlayer
    let language: AppLanguage

    @State private var draftVolume: Double = 35
    @State private var isEditing = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await state.setMuted(!player.muted) }
            } label: {
                Image(systemName: speakerImage)
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(player.muted ? .secondary : .primary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.muted ? language.unmute : language.mute)

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let progress = max(0, min(1, draftVolume / 100))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(nsColor: .tertiaryLabelColor).opacity(0.22))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.primary.opacity(player.muted ? 0.22 : 0.55))
                        .frame(width: max(4, width * progress), height: 4)

                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        .offset(x: max(0, min(width - 14, width * progress - 7)))
                }
                .frame(height: 28)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isEditing = true
                            updateDraftVolume(from: value.location.x, width: width)
                        }
                        .onEnded { value in
                            updateDraftVolume(from: value.location.x, width: width)
                            isEditing = false
                            Task {
                                await state.commitVolume(Int(draftVolume.rounded()))
                            }
                        }
                )
            }
            .frame(height: 28)

            Text(player.muted ? language.off : "\(Int(draftVolume.rounded()))")
                .font(.system(.callout, design: .rounded).monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(language.volume)
        .accessibilityValue(language.volumeValue(isMuted: player.muted, volume: Int(draftVolume.rounded())))
        .onAppear {
            draftVolume = Double(player.volume)
        }
        .onChange(of: player.volume) { _, newValue in
            guard !isEditing else { return }
            draftVolume = Double(newValue)
        }
    }

    private func updateDraftVolume(from locationX: CGFloat, width: CGFloat) {
        let ratio = max(0, min(1, locationX / width))
        let newValue = (ratio * 100).rounded()
        draftVolume = newValue
        state.updateVolumeLive(Int(newValue))
    }

    private var speakerImage: String {
        if player.muted {
            return "speaker.slash.fill"
        }

        switch draftVolume {
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
