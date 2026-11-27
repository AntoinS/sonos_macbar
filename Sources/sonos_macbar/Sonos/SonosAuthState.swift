import Foundation

enum SonosConnectionMode: String, CaseIterable {
    case cloud
    case local
}

enum SonosAuthState: Equatable {
    case checking
    case notConfigured
    case disconnected
    case openingBrowser
    case waitingForAuthorization
    case connected
    case refreshing
    case sessionUnavailable
    case failed(message: String)

    func userMessage(for language: AppLanguage) -> String {
        language.authMessage(for: self)
    }
}

enum SonosConnectionIssue: Equatable {
    case rateLimited(retryAt: Date)
    case sessionUnavailable
    case cloudRequestFailed
    case localRequestFailed
}
