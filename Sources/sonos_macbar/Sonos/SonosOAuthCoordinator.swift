import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class SonosOAuthCoordinator {
    private let authClient: SonosAuthClient
    private let tokenStore: SonosTokenStore
    private let auth: SonosAuth?
    private var loginTask: Task<Void, Never>?
    private var activeLoginId: String?
    private var authorizationURL: URL?

    private(set) var authState: SonosAuthState = .checking

    init(
        authClient: SonosAuthClient = SonosAuthClient(),
        tokenStore: SonosTokenStore = SonosTokenStore(),
        auth: SonosAuth? = nil
    ) {
        self.authClient = authClient
        self.tokenStore = tokenStore
        self.auth = auth
    }

    func prepareAtLaunch() async {
        if let auth, (try? await auth.accessToken()) != nil {
            authState = .connected
            return
        }

        if auth == nil, await tokenStore.savedCredentials()?.validAccessToken != nil {
            authState = .connected
            return
        }

        authState = .disconnected
    }

    func beginLogin(onConnected: @escaping @MainActor () async -> Void) {
        guard loginTask == nil else { return }

        loginTask = Task { [weak self] in
            await self?.runLogin(onConnected: onConnected)
        }
    }

    func reopenBrowser() {
        guard let authorizationURL else { return }
        NSWorkspace.shared.open(authorizationURL)
    }

    func cancelLogin() {
        loginTask?.cancel()
        loginTask = nil
        activeLoginId = nil
        authorizationURL = nil
        authState = .disconnected
    }

    func handleCallback(_ url: URL) {
        guard url.scheme == "sonos-macbar",
              url.host == "oauth",
              url.path == "/complete",
              let loginId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "login_id" })?
                .value,
              loginId == activeLoginId else {
            return
        }
    }

    func disconnect() async throws {
        cancelLogin()
        try await tokenStore.deleteAllSonosCredentials()
        await auth?.clearCachedAccessToken()
        authState = .disconnected
    }

    private func runLogin(onConnected: @escaping @MainActor () async -> Void) async {
        defer {
            loginTask = nil
            activeLoginId = nil
            authorizationURL = nil
        }

        do {
            authState = .checking
            let health = try await authClient.health()
            guard health.oauthConfigured else {
                authState = .notConfigured
                return
            }

            authState = .openingBrowser
            let start = try await authClient.startOAuth()
            activeLoginId = start.loginId
            authorizationURL = start.authorizationURL

            authState = .waitingForAuthorization
            NSWorkspace.shared.open(start.authorizationURL)
            try await Self.pollLogin(loginId: start.loginId, authClient: authClient)

            authState = .refreshing
            let token = try await authClient.token(loginId: start.loginId)
            try await tokenStore.saveCredentials(
                SonosStoredCredentials(
                    brokerSessionId: start.loginId,
                    accessToken: token.accessToken,
                    accessTokenExpiresAt: token.expiresAt
                )
            )
            await auth?.cacheAccessToken(token.accessToken, expiresAt: token.expiresAt)
            authState = .connected
            await onConnected()
        } catch is CancellationError {
            authState = .disconnected
        } catch {
            authState = .failed(message: userMessage(for: error))
        }
    }

    private static func pollLogin(loginId: String, authClient: SonosAuthClient) async throws {
        try await Task.sleep(for: .seconds(1))
        let deadline = Date().addingTimeInterval(600)

        while Date() < deadline {
            try Task.checkCancellation()

            do {
                let response = try await authClient.oauthStatus(loginId: loginId)
                switch response.status {
                case .pending:
                    break
                case .complete:
                    return
                case .failed:
                    throw SonosOAuthCoordinatorError.authorizationDeclined
                }
            } catch let error as SonosAuthClientError {
                if case .requestFailed(statusCode: 404) = error {
                    throw error
                }
            }

            try await Task.sleep(for: .seconds(2))
        }

        throw SonosOAuthCoordinatorError.loginExpired
    }

    private func validateCallback(_ url: URL, expectedLoginId: String) throws {
        guard url.scheme == "sonos-macbar",
              url.host == "oauth",
              url.path == "/complete",
              let loginId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "login_id" })?
                .value,
              loginId == expectedLoginId else {
            throw SonosOAuthCoordinatorError.invalidCallback
        }
    }

    private func userMessage(for error: Error) -> String {
        if let coordinatorError = error as? SonosOAuthCoordinatorError {
            return coordinatorError.localizedDescription
        }

        if let localizedError = error as? LocalizedError,
           let message = localizedError.errorDescription {
            return message
        }

        return "Keine Verbindung zum Sonos-Dienst."
    }
}

enum SonosOAuthCoordinatorError: LocalizedError {
    case authorizationDeclined
    case invalidCallback
    case loginExpired

    var errorDescription: String? {
        switch self {
        case .authorizationDeclined:
            "Die Sonos-Anmeldung wurde abgebrochen."
        case .invalidCallback:
            "Die Sonos-Anmeldung konnte nicht bestätigt werden."
        case .loginExpired:
            "Die Anmeldung ist abgelaufen. Bitte versuche es erneut."
        }
    }
}
