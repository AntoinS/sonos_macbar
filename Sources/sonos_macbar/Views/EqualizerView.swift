import SwiftUI

struct EqualizerView: View {
    let language: AppLanguage
    @Binding var isExpanded: Bool
    @State private var state: EqualizerState
    @State private var reloadCount = 0

    init(playerID: SonosPlayer.ID, language: AppLanguage, isExpanded: Binding<Bool>) {
        self.language = language
        _isExpanded = isExpanded
        _state = State(initialValue: EqualizerState(playerID: playerID))
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if isExpanded {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                    .task(id: reloadCount) {
                        await state.load()
                    }
            }
        } label: {
            Label("Equalizer", systemImage: "slider.horizontal.3")
                .font(.callout.weight(.medium))
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
                VStack(alignment: .leading, spacing: 6) {
                    slider(.bass)
                    slider(.treble)
                    if let loudness = state.values[.loudness] {
                        Toggle("Loudness", isOn: Binding(
                            get: { loudness == 1 },
                            set: { save(.loudness, value: $0 ? 1 : 0) }
                        ))
                        .toggleStyle(.switch)
                    }
                    slider(.subLevel)
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
            EqualizerSlider(title: language.equalizerLabel(control), value: value, range: control.range) {
                save(control, value: $0)
            }
        }
    }

    private func save(_ control: EqualizerControl, value: Int) {
        Task { await state.save(control, value: value) }
    }
}

private struct EqualizerSlider: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let save: (Int) -> Void
    @State private var draft: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(title, value: (draft.map(Int.init) ?? value).formatted())
                .monospacedDigit()
                .accessibilityHidden(true)
            Slider(value: Binding(
                get: { draft ?? Double(value) },
                set: { newValue in
                    if draft != nil {
                        draft = newValue
                    } else {
                        save(Int(newValue))
                    }
                }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: 1) {
                Text(title)
            } onEditingChanged: { editing in
                if editing {
                    draft = Double(value)
                } else if let draft {
                    self.draft = nil
                    save(Int(draft))
                }
            }
            .labelsHidden()
            .accessibilityLabel(title)
        }
    }
}
