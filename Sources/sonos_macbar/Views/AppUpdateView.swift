import SwiftUI

struct AppUpdateView: View {
    let language: AppLanguage
    private let updater = AppUpdater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                PanelIcon("arrow.down.circle.fill", tint: .teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Updates")
                        .font(.callout)
                    versionLine
                }
                Spacer(minLength: 4)
                if showsUpdateButton {
                    updateButton.controlSize(.small)
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
                case .idle, .current:
                    if let version = updater.availableVersion {
                        message(language.isGerman ? "v\(version) verfügbar" : "v\(version) available", icon: "arrow.down.circle")
                    }
                case let .failed(detail):
                    message(language.isGerman ? "Update fehlgeschlagen" : "Update failed", icon: "exclamationmark.circle")
                        .help(detail)
                }
            } else {
                message(language.isGerman ? "Updates in diesem Build nicht verfügbar" : "Updates unavailable in this build", icon: "info.circle")
            }
        }
    }

    private var versionLine: some View {
        HStack(spacing: 7) {
            if let version = updater.installedVersion {
                Text("v\(version)")
                    .monospacedDigit()
                    .accessibilityLabel(language.isGerman ? "Installierte Version \(version)" : "Installed version \(version)")
            }
            if case .current = updater.status, updater.availableVersion == nil {
                Label(language.isGerman ? "Aktuell" : "Up to date", systemImage: "checkmark.circle")
                    .imageScale(.small)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var updateButton: some View {
        if updater.availableVersion != nil {
            Button(action: updater.performUpdateAction) {
                Label(language.isGerman ? "Aktualisieren" : "Update", systemImage: "arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        } else {
            Button(action: updater.performUpdateAction) {
                Label(language.isGerman ? "Prüfen" : "Check", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help(language.isGerman ? "Nach Updates suchen" : "Check for updates")
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
