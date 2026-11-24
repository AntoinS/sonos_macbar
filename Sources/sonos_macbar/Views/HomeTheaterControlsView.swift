import SwiftUI

struct HomeTheaterControlsView: View {
    let state: SonosState
    let player: SonosPlayer
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            if player.supportsEnhanceDialog {
                ControlCenterToggleButton(
                    title: language.voice,
                    systemImage: "text.bubble.fill",
                    isOn: player.enhanceDialog,
                    language: language
                ) {
                    Task { await state.setEnhanceDialog(!player.enhanceDialog) }
                }
            }

            if player.supportsNightMode {
                ControlCenterToggleButton(
                    title: language.night,
                    systemImage: "moon.fill",
                    isOn: player.nightMode,
                    language: language
                ) {
                    Task { await state.setNightMode(!player.nightMode) }
                }
            }
        }
    }
}

private struct ControlCenterToggleButton: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(isOn ? Color.blue : .secondary)
                .frame(maxWidth: .infinity, minHeight: 29)
                .background(
                    isOn ? Color.blue.opacity(0.13) : .primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? language.on : language.off)
    }
}

#Preview {
    HomeTheaterControlsView(state: SonosState(service: MockSonosService()), player: .mockArc, language: .english)
        .padding()
        .frame(width: 340)
}
