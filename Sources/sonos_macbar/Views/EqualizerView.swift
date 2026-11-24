import SwiftUI

struct EqualizerView: View {
    let player: SonosPlayer
    let language: AppLanguage
    let onClose: () -> Void
    @State private var state: EqualizerState
    @State private var reloadCount = 0

    init(player: SonosPlayer, language: AppLanguage, onClose: @escaping () -> Void) {
        self.player = player
        self.language = language
        self.onClose = onClose
        _state = State(initialValue: EqualizerState(playerID: player.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: "Equalizer", closeLabel: language.close, onClose: onClose)
            Text(player.roomName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: reloadCount) {
            await state.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.status {
        case .loading:
            ProgressView(language.equalizerLoading)
                .controlSize(.small)
        case .unavailable:
            VStack(alignment: .leading, spacing: 6) {
                Text(language.equalizerUnavailable)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(language.retry) { reloadCount += 1 }
                    .controlSize(.small)
            }
        case .ready:
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 8) {
                    slider(.bass)
                    slider(.treble)
                    slider(.subLevel)
                    if let loudness = state.values[.loudness] {
                        Toggle(language.equalizerLabel(.loudness), isOn: Binding(
                            get: { loudness == 1 },
                            set: { save(.loudness, value: $0 ? 1 : 0) }
                        ))
                        .toggleStyle(.switch)
                    }
                }
                .disabled(state.isSaving)

                if let change = state.failedChange {
                    Text(language.equalizerWriteFailed)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(language.retry) { save(change.control, value: change.value) }
                        .controlSize(.small)
                }
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private func slider(_ control: EqualizerControl) -> some View {
        if let value = state.values[control] {
            let title = language.equalizerLabel(control)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                AudioSlider(title: title, value: value, range: control.range) {
                    save(control, value: $0)
                }
            }
        }
    }

    private func save(_ control: EqualizerControl, value: Int) {
        Task { await state.save(control, value: value) }
    }
}
