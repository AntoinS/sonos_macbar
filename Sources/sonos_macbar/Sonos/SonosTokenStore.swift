import Foundation
import Security

struct SonosTokenStore: Sendable {
    private let environment: [String: String]
    private let developmentAccessTokenEnvironmentKey: String

    private let credentialsService = "de.alania.sonos-macbar.credentials"
    private let brokerSessionService = "de.alania.sonos-macbar.broker-session"
    private let accessTokenService = "de.alania.sonos-macbar.access-token"
    private let accessExpiryService = "de.alania.sonos-macbar.access-expiry"
    private let keychainAccount: String

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configuration: SonosAuthConfiguration = .production,
        keychainAccount: String = "default"
    ) {
        self.environment = environment
        self.developmentAccessTokenEnvironmentKey = configuration.developmentAccessTokenEnvironmentKey
        self.keychainAccount = keychainAccount
    }

    func savedCredentials() async throws -> SonosStoredCredentials? {
        try await keychainData(service: credentialsService).map { data in
            try JSONDecoder().decode(SonosStoredCredentials.self, from: data)
        }
    }

    func legacyBrokerSessionId() async throws -> String? {
        try await keychainString(service: brokerSessionService)
    }

    func developmentAccessToken() -> String? {
        #if DEBUG
        environment[developmentAccessTokenEnvironmentKey].flatMap(Self.nonEmptyToken)
        #else
        nil
        #endif
    }

    func saveCredentials(_ credentials: SonosStoredCredentials) async throws {
        try await saveData(JSONEncoder().encode(credentials), service: credentialsService)
        try await deleteLegacyCredentials()
    }

    func deleteAccessTokenFromCredentials() async throws {
        guard var credentials = try await savedCredentials() else {
            try await deleteString(service: accessTokenService)
            try await deleteString(service: accessExpiryService)
            return
        }

        credentials.accessToken = nil
        credentials.accessTokenExpiresAt = nil
        try await saveData(JSONEncoder().encode(credentials), service: credentialsService)
        try await deleteString(service: accessTokenService)
        try await deleteString(service: accessExpiryService)
    }

    func deleteAllSonosCredentials() async throws {
        try await deleteString(service: credentialsService)
        try await deleteLegacyCredentials()
    }

    private func deleteLegacyCredentials() async throws {
        try await deleteString(service: brokerSessionService)
        try await deleteString(service: accessTokenService)
        try await deleteString(service: accessExpiryService)
    }

    private func saveString(_ value: String, service: String) async throws {
        guard let value = Self.nonEmptyToken(value),
              let data = value.data(using: .utf8) else {
            throw SonosTokenStoreError.emptyToken
        }

        try await saveData(data, service: service)
    }

    private func saveData(_ data: Data, service: String) async throws {
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

    private func keychainString(service: String) async throws -> String? {
        guard let data = try await keychainData(service: service),
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return Self.nonEmptyToken(value)
    }

    private func keychainData(service: String) async throws -> Data? {
        var query = keychainBaseQuery(service: service)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SonosTokenStoreError.keychainFailure(status)
        }

        return item as? Data
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

struct SonosStoredCredentials: Codable, Equatable, Sendable {
    var brokerSessionId: String
    var accessToken: String?
    var accessTokenExpiresAt: Date?

    var validAccessToken: String? {
        guard let accessToken = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessToken.isEmpty else {
            return nil
        }

        guard let accessTokenExpiresAt else { return accessToken }
        return accessTokenExpiresAt > Date().addingTimeInterval(120) ? accessToken : nil
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
