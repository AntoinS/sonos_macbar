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

    func userMessage(for language: AppLanguage) -> String {
        language.authMessage(for: self)
    }
}
