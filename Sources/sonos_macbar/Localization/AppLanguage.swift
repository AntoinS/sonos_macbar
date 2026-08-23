import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case german

    static let storageKey = "appLanguage"

    var id: String { rawValue }

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

    var none: String {
        switch self {
        case .english:
            "None"
        case .german:
            "Keiner"
        }
    }

    var status: String {
        switch self {
        case .english:
            "Status"
        case .german:
            "Status"
        }
    }

    var login: String {
        switch self {
        case .english:
            "Login"
        case .german:
            "Anmeldung"
        }
    }

    var session: String {
        switch self {
        case .english:
            "Session"
        case .german:
            "Sitzung"
        }
    }

    var token: String {
        switch self {
        case .english:
            "Token"
        case .german:
            "Token"
        }
    }

    var language: String {
        switch self {
        case .english:
            "Language"
        case .german:
            "Sprache"
        }
    }

    var stored: String {
        switch self {
        case .english:
            "Stored"
        case .german:
            "Gespeichert"
        }
    }

    var notStored: String {
        switch self {
        case .english:
            "Not stored"
        case .german:
            "Nicht gespeichert"
        }
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
            "Sprache"
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

    func connectionStatus(isLoading: Bool, isAuthenticationRequired: Bool, hasError: Bool) -> String {
        if isLoading {
            switch self {
            case .english:
                return "Connecting"
            case .german:
                return "Verbinden"
            }
        }

        if isAuthenticationRequired {
            switch self {
            case .english:
                return "Not Connected"
            case .german:
                return "Nicht verbunden"
            }
        }

        if hasError {
            return "Offline"
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
        case .offline:
            switch self {
            case .english:
                return "Sonos is currently unavailable."
            case .german:
                return "Sonos ist gerade nicht erreichbar."
            }
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
        case .offline:
            switch self {
            case .english:
                return "Sonos Is Currently Unavailable"
            case .german:
                return "Sonos ist gerade nicht erreichbar"
            }
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
        case .offline:
            switch self {
            case .english:
                return "The connection will be retried automatically."
            case .german:
                return "Die Verbindung wird automatisch erneut versucht."
            }
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
