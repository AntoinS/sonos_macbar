import Foundation

enum SonosAuthState: Equatable {
    case checking
    case notConfigured
    case disconnected
    case openingBrowser
    case waitingForAuthorization
    case connected
    case refreshing
    case offline
    case failed(message: String)

    var userMessage: String {
        switch self {
        case .checking:
            "Sonos-Verbindung wird geprüft."
        case .notConfigured:
            "Sonos-Anmeldung wird derzeit eingerichtet."
        case .disconnected:
            "Sonos ist nicht verbunden."
        case .openingBrowser:
            "Anmeldung im Browser öffnen."
        case .waitingForAuthorization:
            "Anmeldung im Browser abschließen."
        case .connected:
            "Sonos verbunden."
        case .refreshing:
            "Sonos-Verbindung wird erneuert."
        case .offline:
            "Sonos ist gerade nicht erreichbar."
        case let .failed(message):
            message
        }
    }
}
