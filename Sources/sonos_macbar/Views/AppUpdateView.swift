import SwiftUI

struct AppUpdateView: View {
    let language: AppLanguage
    private let updater = AppUpdater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                SettingsIcon("arrow.down.circle.fill", tint: .teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Updates")
                        .font(.callout)
                    if let version = updater.installedVersion {
                        Text("v\(version)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(language.isGerman ? "Installierte Version \(version)" : "Installed version \(version)")
                    }
                }
                Spacer(minLength: 4)
                if showsUpdateButton {
                    Button(action: updater.checkForUpdates) {
                        Label(language.isGerman ? "Aktualisieren" : "Update", systemImage: "arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if updater.isConfigured {
                switch updater.status {
                case .checking:
                    progress(language.isGerman ? "Wird geprüft …" : "Checking…")
                case let .downloading(value):
                    progress(language.isGerman ? "Wird geladen …" : "Downloading…", value: value)
                case let .extracting(value):
                    progress(language.isGerman ? "Wird vorbereitet …" : "Preparing…", value: value)
                case .installing:
                    progress(language.isGerman ? "Installation und Neustart …" : "Installing and restarting…")
                case .current:
                    message(language.isGerman ? "Auf dem neuesten Stand" : "Up to date", icon: "checkmark.circle")
                case let .failed(detail):
                    message(language.isGerman ? "Update fehlgeschlagen" : "Update failed", icon: "exclamationmark.circle")
                        .help(detail)
                case .idle:
                    EmptyView()
                }
            } else {
                message(language.isGerman ? "Updates in diesem Build nicht verfügbar" : "Updates unavailable in this build", icon: "info.circle")
            }
        }
    }

    private var showsUpdateButton: Bool {
        guard updater.isConfigured else { return false }
        switch updater.status {
        case .idle, .current, .failed: return true
        case .checking, .downloading, .extracting, .installing: return false
        }
    }

    private func progress(_ title: String, value: Double? = nil) -> some View {
        ProgressView(value: value) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .progressViewStyle(.linear)
    }

    private func message(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
