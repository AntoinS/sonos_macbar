import Foundation
import Security

struct SonosTokenStore: Sendable {
    private let environment: [String: String]
    private let developmentAccessTokenEnvironmentKey: String

    private let brokerSessionService = "de.alania.sonos-macbar.broker-session"
    private let accessTokenService = "de.alania.sonos-macbar.access-token"
    private let accessExpiryService = "de.alania.sonos-macbar.access-expiry"
    private let keychainAccount = "default"

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configuration: SonosAuthConfiguration = .production
    ) {
        self.environment = environment
        self.developmentAccessTokenEnvironmentKey = configuration.developmentAccessTokenEnvironmentKey
    }

    func accessToken() async -> String? {
        if let keychainToken = await savedAccessToken(), await isAccessTokenValid() {
            return keychainToken
        }

        #if DEBUG
        return environment[developmentAccessTokenEnvironmentKey].flatMap(Self.nonEmptyToken)
        #else
        return nil
        #endif
    }

    func savedAccessToken() async -> String? {
        await keychainString(service: accessTokenService)
    }

    func brokerSessionId() async -> String? {
        await keychainString(service: brokerSessionService)
    }

    func saveBrokerSessionId(_ loginId: String) async throws {
        try await saveString(loginId, service: brokerSessionService)
    }

    func saveAccessToken(_ token: String, expiresAt: Date? = nil) async throws {
        try await saveString(token, service: accessTokenService)

        if let expiresAt {
            try await saveString(String(Int(expiresAt.timeIntervalSince1970)), service: accessExpiryService)
        }
    }

    func deleteSavedAccessToken() async throws {
        try await deleteString(service: accessTokenService)
        try await deleteString(service: accessExpiryService)
    }

    func deleteAllSonosCredentials() async throws {
        try await deleteString(service: brokerSessionService)
        try await deleteString(service: accessTokenService)
        try await deleteString(service: accessExpiryService)
    }

    private func isAccessTokenValid() async -> Bool {
        guard let expiryString = await keychainString(service: accessExpiryService),
              let expiryTimestamp = TimeInterval(expiryString) else {
            return true
        }

        return Date(timeIntervalSince1970: expiryTimestamp) > Date().addingTimeInterval(120)
    }

    private func saveString(_ value: String, service: String) async throws {
        guard let value = Self.nonEmptyToken(value),
              let data = value.data(using: .utf8) else {
            throw SonosTokenStoreError.emptyToken
        }

        let query = keychainBaseQuery(service: service)
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw SonosTokenStoreError.keychainFailure(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SonosTokenStoreError.keychainFailure(addStatus)
        }
    }

    private func deleteString(service: String) async throws {
        let status = SecItemDelete(keychainBaseQuery(service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SonosTokenStoreError.keychainFailure(status)
        }
    }

    private func keychainString(service: String) async -> String? {
        var query = keychainBaseQuery(service: service)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return Self.nonEmptyToken(value)
    }

    private func keychainBaseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount
        ]
    }

    private static func nonEmptyToken(_ token: String) -> String? {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedToken.isEmpty ? nil : trimmedToken
    }
}

enum SonosTokenStoreError: LocalizedError {
    case emptyToken
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyToken:
            "Der Token ist leer."
        case .keychainFailure:
            "Die Sonos-Zugangsdaten konnten nicht im Schlüsselbund gespeichert werden."
        }
    }
}
