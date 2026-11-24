import AppKit

@MainActor
enum HomebrewUpdate {
    private static let executable = "/opt/homebrew/bin/brew"

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: executable)
    }

    static func openInTerminal() async throws {
        guard isAvailable,
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            throw CocoaError(.fileNoSuchFile)
        }

        let files = FileManager.default
        let directory = files.temporaryDirectory.appending(path: "SonosMacbarUpdate-\(UUID())", directoryHint: .isDirectory)
        let command = directory.appending(path: "Update Sonos Macbar.command")
        try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])

        do {
            try script.write(to: command, atomically: true, encoding: .utf8)
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: command.path)
            _ = try await NSWorkspace.shared.open([command], withApplicationAt: terminal, configuration: .init())
        } catch {
            try? files.removeItem(at: directory)
            throw error
        }
    }

    static var script: String {
        """
        #!/bin/bash
        set -e
        cleanup() {
            /bin/rm -f -- "$0"
            /bin/rmdir -- "$(/usr/bin/dirname "$0")"
        }
        trap cleanup EXIT
        \(executable) update
        HOMEBREW_NO_INSTALL_CLEANUP=1 \(executable) upgrade --cask antoins/sonos_macbar/sonos-macbar
        /usr/bin/printf '\\nQuit and reopen Sonos Macbar to use the new version.\\n'

        """
    }
}
