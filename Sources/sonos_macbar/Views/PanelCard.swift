import SwiftUI

struct PanelCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content.background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PanelIcon: View {
    let symbol: String
    let tint: Color

    init(_ symbol: String, tint: Color) {
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
    }
}

struct PanelIconButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 27, height: 24)
                .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }
}
