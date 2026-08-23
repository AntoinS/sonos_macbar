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
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? Color.accentColor : .primary)
            .frame(maxWidth: .infinity, minHeight: 34)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isOn ? 0.68 : 0.34))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isOn ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.06), lineWidth: 1)
            )
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
