import AppKit
import SwiftUI

struct AppUpdateView: View {
    let language: AppLanguage
    @State private var status: Status = .idle
    @State private var homebrewMessage: HomebrewMessage?

    private enum Status {
        case idle, checking, current, failed
        case available(AppUpdate)
    }

    private enum HomebrewMessage: Equatable {
        case opening, opened, failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Updates")
                .font(.callout.weight(.semibold))

            if let version = AppUpdateService.installedVersion {
                LabeledContent(language.isGerman ? "Installierte Version" : "Installed Version", value: version)
                    .font(.callout)
                Button {
                    Task { await check(installedVersion: version) }
                } label: {
                    Label(
                        language.isGerman ? "Nach Updates suchen" : "Check for Updates",
                        systemImage: "arrow.clockwise"
                    )
                    .frame(maxWidth: .infinity)
                }
                .disabled(isChecking)
                result
            } else {
                message(language.isGerman ? "Updates sind im Testbuild nicht verfügbar." : "Updates are unavailable in development builds.")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    @ViewBuilder
    private var result: some View {
        switch status {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView(language.isGerman ? "Suche nach Updates …" : "Checking for updates…")
                .controlSize(.small)
        case .current:
            message(language.isGerman ? "Du hast die aktuelle Version." : "You’re up to date.")
        case .failed:
            message(language.isGerman ? "Die Update-Suche ist fehlgeschlagen. Versuche es später erneut." : "Couldn’t check for updates. Try again later.")
        case let .available(update):
            message(language.isGerman ? "Version \(update.version) ist verfügbar." : "Version \(update.version) is available.")
            if HomebrewUpdate.isAvailable {
                Button {
                    Task { await openHomebrew() }
                } label: {
                    Label(language.isGerman ? "Mit Homebrew aktualisieren" : "Update with Homebrew", systemImage: "terminal")
                        .frame(maxWidth: .infinity)
                }
                .disabled(homebrewMessage == .opening)
            }
            Link(destination: update.downloadURL) {
                Label(language.isGerman ? "Von GitHub laden" : "Download from GitHub", systemImage: "arrow.down.to.line")
            }
            .font(.callout)
            if let homebrewMessage {
                switch homebrewMessage {
                case .opening:
                    message(language.isGerman ? "Terminal wird geöffnet …" : "Opening Terminal…")
                case .opened:
                    message(language.isGerman ? "Folge den Anweisungen im Terminal. Starte die App nach dem Update neu." : "Follow the prompts in Terminal, then reopen the app.")
                case .failed:
                    message(language.isGerman ? "Das Terminal konnte nicht geöffnet werden." : "Couldn’t open Terminal.")
                }
            }
        }
    }

    private var isChecking: Bool {
        if case .checking = status { return true }
        return false
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func check(installedVersion: String) async {
        status = .checking
        homebrewMessage = nil
        do {
            if let update = try await AppUpdateService.check(installedVersion: installedVersion) {
                status = .available(update)
            } else {
                status = .current
            }
        } catch {
            status = .failed
        }
    }

    private func openHomebrew() async {
        homebrewMessage = .opening
        do {
            try await HomebrewUpdate.openInTerminal()
            homebrewMessage = .opened
        } catch {
            homebrewMessage = .failed
        }
    }
}
