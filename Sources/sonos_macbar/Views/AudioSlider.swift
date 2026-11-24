import SwiftUI

struct AudioSlider: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    var isDimmed = false
    var displayValue: (Int) -> String = { String($0) }
    var spokenValue: ((Int) -> String)?
    var onPreview: (Int) -> Void = { _ in }
    let onCommit: (Int) -> Void

    @State private var draft: Int?

    private var currentValue: Int { draft ?? value }

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let progress = min(1, max(0, CGFloat(currentValue - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(nsColor: .tertiaryLabelColor).opacity(0.22))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.primary.opacity(isDimmed ? 0.22 : 0.55))
                        .frame(width: max(4, width * progress), height: 4)

                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.primary.opacity(0.14), lineWidth: 1))
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        .offset(x: max(0, min(width - 14, width * progress - 7)))
                }
                .frame(height: 28)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let value = sliderValue(at: drag.location.x, width: width)
                            draft = value
                            onPreview(value)
                        }
                        .onEnded { drag in
                            let value = sliderValue(at: drag.location.x, width: width)
                            onPreview(value)
                            draft = nil
                            onCommit(value)
                        }
                )
            }
            .frame(height: 28)

            Text(displayValue(currentValue))
                .font(.system(.callout, design: .rounded).monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spokenValue?(currentValue) ?? displayValue(currentValue))
        .accessibilityAdjustableAction { direction in
            let delta: Int
            switch direction {
            case .increment: delta = 1
            case .decrement: delta = -1
            @unknown default: return
            }
            let next = min(range.upperBound, max(range.lowerBound, currentValue + delta))
            guard next != currentValue else { return }
            onPreview(next)
            onCommit(next)
        }
    }

    private func sliderValue(at location: CGFloat, width: CGFloat) -> Int {
        let progress = min(1, max(0, location / width))
        return range.lowerBound + Int((progress * CGFloat(range.upperBound - range.lowerBound)).rounded())
    }
}
