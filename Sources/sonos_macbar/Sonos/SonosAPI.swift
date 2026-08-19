import Foundation

protocol SonosAPI: Sendable {
    func fetchPlayers() async throws -> [SonosPlayer]
    func setVolume(_ volume: Int, for playerID: SonosPlayer.ID) async throws -> SonosPlayer
    func setMuted(_ isMuted: Bool, for playerID: SonosPlayer.ID) async throws -> SonosPlayer
    func setEnhanceDialog(_ isEnabled: Bool, for playerID: SonosPlayer.ID) async throws -> SonosPlayer
    func setNightMode(_ isEnabled: Bool, for playerID: SonosPlayer.ID) async throws -> SonosPlayer
}

enum SonosAPIError: LocalizedError {
    case playerNotFound
    case credentialsRequired
    case invalidResponse
    case noHouseholdFound
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .playerNotFound:
            "Sonos player not found."
        case .credentialsRequired:
            "Bitte verbinde Sonos erneut."
        case .invalidResponse:
            "Die Sonos-Daten konnten nicht gelesen werden."
        case .noHouseholdFound:
            "Für dieses Konto wurde kein Sonos-Haushalt gefunden."
        case let .requestFailed(statusCode, message):
            if let message, !message.isEmpty {
                "Sonos request failed (\(statusCode)): \(message)"
            } else {
                "Sonos request failed with status \(statusCode)."
            }
        }
    }
}
