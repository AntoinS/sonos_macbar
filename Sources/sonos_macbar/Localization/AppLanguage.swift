import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case german

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    var isGerman: Bool { self == .german }

    static var current: AppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: storageKey)
        return rawValue.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    var displayName: String {
        switch self {
        case .english:
            "English"
        case .german:
            "Deutsch"
        }
    }

    func equalizerLabel(_ control: EqualizerControl) -> String {
        switch (self, control) {
        case (_, .bass): "Bass"
        case (.english, .treble): "Treble"
        case (.german, .treble): "Höhen"
        case (_, .loudness): "Loudness"
        case (.english, .subLevel): "Sub Level"
        case (.german, .subLevel): "Sub-Pegel"
        }
    }

    var equalizerLoading: String {
        self == .german ? "Equalizer wird geladen …" : "Loading equalizer…"
    }

    var equalizerUnavailable: String {
        switch self {
        case .english:
            "The equalizer is unavailable. Check that your Mac and Sonos are on the same network and that Sonos Macbar has Local Network access in System Settings."
        case .german:
            "Der Equalizer ist nicht erreichbar. Prüfe, ob Mac und Sonos im selben Netzwerk sind und Sonos Macbar in den Systemeinstellungen Zugriff auf das lokale Netzwerk hat."
        }
    }

    var equalizerWriteFailed: String {
        self == .german ? "Die Änderung konnte nicht übernommen werden." : "The change couldn’t be applied."
    }

    var settingsTitle: String {
        switch self {
        case .english:
            "Settings"
        case .german:
            "Einstellungen"
        }
    }

    var quitApp: String {
        switch self {
        case .english:
            "Quit Sonos Macbar"
        case .german:
            "Sonos Macbar beenden"
        }
    }

    var close: String {
        switch self {
        case .english:
            "Close"
        case .german:
            "Schliessen"
        }
    }

    var room: String {
        switch self {
        case .english:
            "Room"
        case .german:
            "Raum"
        }
    }

    var noRoom: String {
        switch self {
        case .english:
            "No Room"
        case .german:
            "Kein Raum"
        }
    }

    var notConnected: String {
        isGerman ? "Nicht verbunden" : "Not connected"
    }

    var language: String {
        switch self {
        case .english:
            "Language"
        case .german:
            "Sprache"
        }
    }

    var browserLogin: String {
        isGerman ? "Anmeldung im Browser" : "Sign in via browser"
    }

    var loading: String {
        switch self {
        case .english:
            "Loading"
        case .german:
            "Lädt"
        }
    }

    var reloadRooms: String {
        switch self {
        case .english:
            "Reload Rooms"
        case .german:
            "Räume neu laden"
        }
    }

    var connectSonos: String {
        switch self {
        case .english:
            "Connect Sonos"
        case .german:
            "Sonos verbinden"
        }
    }

    var connectToSonos: String {
        switch self {
        case .english:
            "Connect to Sonos"
        case .german:
            "Mit Sonos verbinden"
        }
    }

    var disconnect: String {
        switch self {
        case .english:
            "Disconnect"
        case .german:
            "Trennen"
        }
    }

    var disconnectConnection: String {
        switch self {
        case .english:
            "Disconnect"
        case .german:
            "Verbindung trennen"
        }
    }

    var disconnectSonosQuestion: String {
        isGerman ? "Sonos trennen?" : "Disconnect Sonos?"
    }

    var cancel: String {
        switch self {
        case .english:
            "Cancel"
        case .german:
            "Abbrechen"
        }
    }

    var retry: String {
        switch self {
        case .english:
            "Try Again"
        case .german:
            "Erneut versuchen"
        }
    }

    func connectionIssueTitle(for issue: SonosConnectionIssue) -> String {
        switch issue {
        case .rateLimited:
            isGerman ? "Sonos-Anfragelimit (429)" : "Sonos Rate Limit (429)"
        case .sessionUnavailable:
            isGerman ? "Sitzungsprüfung fehlgeschlagen" : "Session Check Failed"
        case .cloudRequestFailed:
            isGerman ? "Cloud-Steuerung gestört" : "Cloud Control Unavailable"
        }
    }

    func connectionIssueMessage(for issue: SonosConnectionIssue) -> String {
        switch issue {
        case let .rateLimited(retryAt):
            let date = retryAt.formatted(
                Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Locale(identifier: isGerman ? "de_DE" : "en_US"))
            )
            return isGerman
                ? "Sonos begrenzt die Steueranfragen. Nächster Versuch ab \(date)."
                : "Sonos is limiting control requests. Next attempt from \(date)."
        case .sessionUnavailable:
            return isGerman
                ? "Die gespeicherte Anmeldung wird automatisch erneut geprüft."
                : "Your saved sign-in will be checked again automatically."
        case .cloudRequestFailed:
            return isGerman
                ? "Die letzte Anfrage an die Sonos-Cloud ist fehlgeschlagen."
                : "The latest request to the Sonos cloud failed."
        }
    }

    var reopenBrowser: String {
        switch self {
        case .english:
            "Reopen Browser"
        case .german:
            "Browser erneut öffnen"
        }
    }

    var voice: String {
        switch self {
        case .english:
            "Voice"
        case .german:
            "Dialog"
        }
    }

    var night: String {
        switch self {
        case .english:
            "Night"
        case .german:
            "Nacht"
        }
    }

    var on: String {
        switch self {
        case .english:
            "On"
        case .german:
            "Ein"
        }
    }

    var off: String {
        switch self {
        case .english:
            "Off"
        case .german:
            "Aus"
        }
    }

    var mute: String {
        switch self {
        case .english:
            "Mute"
        case .german:
            "Stummschalten"
        }
    }

    var unmute: String {
        switch self {
        case .english:
            "Unmute"
        case .german:
            "Ton einschalten"
        }
    }

    var volume: String {
        switch self {
        case .english:
            "Volume"
        case .german:
            "Lautstärke"
        }
    }

    var source: String {
        switch self {
        case .english:
            "Source"
        case .german:
            "Quelle"
        }
    }

    func volumeValue(isMuted: Bool, volume: Int) -> String {
        isMuted ? muted : "\(volume) percent"
    }

    var muted: String {
        switch self {
        case .english:
            "Muted"
        case .german:
            "Stumm"
        }
    }

    func connectionStatus(isLoading: Bool, isAuthenticationRequired: Bool) -> String {
        if isLoading {
            switch self {
            case .english:
                return "Connecting"
            case .german:
                return "Verbinden"
            }
        }

        if isAuthenticationRequired {
            return notConnected
        }

        switch self {
        case .english:
            return "Connected"
        case .german:
            return "Verbunden"
        }
    }

    func authMessage(for state: SonosAuthState) -> String {
        switch state {
        case .checking:
            switch self {
            case .english:
                return "Checking Sonos connection."
            case .german:
                return "Sonos-Verbindung wird geprüft."
            }
        case .notConfigured:
            switch self {
            case .english:
                return "Sonos login is being set up."
            case .german:
                return "Sonos-Anmeldung wird derzeit eingerichtet."
            }
        case .disconnected:
            switch self {
            case .english:
                return "Sonos is not connected."
            case .german:
                return "Sonos ist nicht verbunden."
            }
        case .openingBrowser:
            switch self {
            case .english:
                return "Opening login in the browser."
            case .german:
                return "Anmeldung im Browser öffnen."
            }
        case .waitingForAuthorization:
            switch self {
            case .english:
                return "Complete login in the browser."
            case .german:
                return "Anmeldung im Browser abschließen."
            }
        case .connected:
            switch self {
            case .english:
                return "Sonos connected."
            case .german:
                return "Sonos verbunden."
            }
        case .refreshing:
            switch self {
            case .english:
                return "Refreshing Sonos connection."
            case .german:
                return "Sonos-Verbindung wird erneuert."
            }
        case .sessionUnavailable:
            return connectionIssueMessage(for: .sessionUnavailable)
        case let .failed(message):
            return message
        }
    }

    func connectionTitle(for state: SonosAuthState) -> String {
        switch state {
        case .checking:
            switch self {
            case .english:
                return "Checking Sonos Connection"
            case .german:
                return "Sonos-Verbindung prüfen"
            }
        case .notConfigured:
            switch self {
            case .english:
                return "Sonos Login Is Being Set Up"
            case .german:
                return "Sonos-Anmeldung wird eingerichtet"
            }
        case .openingBrowser, .waitingForAuthorization:
            switch self {
            case .english:
                return "Complete Login in Browser"
            case .german:
                return "Anmeldung im Browser abschließen"
            }
        case .sessionUnavailable:
            return connectionIssueTitle(for: .sessionUnavailable)
        case .failed:
            switch self {
            case .english:
                return "Sonos Could Not Connect"
            case .german:
                return "Sonos konnte nicht verbunden werden"
            }
        default:
            switch self {
            case .english:
                return "Sonos Is Not Connected"
            case .german:
                return "Sonos ist nicht verbunden"
            }
        }
    }

    func connectionMessage(for state: SonosAuthState) -> String {
        switch state {
        case .notConfigured:
            switch self {
            case .english:
                return "Sonos login is not available on the server yet."
            case .german:
                return "Die Sonos-Anmeldung ist serverseitig noch nicht verfügbar."
            }
        case .openingBrowser, .waitingForAuthorization:
            switch self {
            case .english:
                return "Sign in to Sonos and allow access."
            case .german:
                return "Melde dich bei Sonos an und erlaube den Zugriff."
            }
        case .sessionUnavailable:
            return connectionIssueMessage(for: .sessionUnavailable)
        case let .failed(message):
            return message
        default:
            switch self {
            case .english:
                return "Connect your Sonos account to control rooms and playback."
            case .german:
                return "Verbinde dein Sonos-Konto, um Räume und Wiedergabe zu steuern."
            }
        }
    }
}
