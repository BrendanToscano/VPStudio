import Foundation
import Security

protocol SecretStore: Sendable {
    func setSecret(_ secret: String, for key: String) async throws
    func getSecret(for key: String) async throws -> String?
    func deleteSecret(for key: String) async throws
    func deleteAllSecrets() async throws
}

enum SecretStoreError: LocalizedError, Equatable {
    case unexpectedStatus(OSStatus, operation: String)
    case invalidSecretData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status, let operation):
            return "Keychain \(operation) failed with status \(status)"
        case .invalidSecretData:
            return "Stored secret data is invalid"
        }
    }
}

actor KeychainSecretStore: SecretStore {
    private let serviceName: String

    init(serviceName: String = "com.vpstudio.credentials") {
        self.serviceName = serviceName
    }

    func setSecret(_ secret: String, for key: String) async throws {
        let encoded = Data(secret.utf8)
        let query = baseQuery(for: key)
        let update: [String: Any] = [kSecValueData as String: encoded]

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw SecretStoreError.unexpectedStatus(updateStatus, operation: "update")
        }

        var addQuery = query
        addQuery[kSecValueData as String] = encoded
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecretStoreError.unexpectedStatus(addStatus, operation: "add")
        }
    }

    func getSecret(for key: String) async throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SecretStoreError.unexpectedStatus(status, operation: "read")
        }
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.invalidSecretData
        }
        return secret
    }

    func deleteSecret(for key: String) async throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(status, operation: "delete")
        }
    }

    func deleteAllSecrets() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(status, operation: "deleteAll")
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
    }
}

enum SecretReference {
    static let keychainPrefix = "keychain:"

    nonisolated static func encode(key: String) -> String {
        "\(keychainPrefix)\(key)"
    }

    nonisolated static func decode(_ storedValue: String) -> String? {
        guard storedValue.hasPrefix(keychainPrefix) else { return nil }
        return String(storedValue.dropFirst(keychainPrefix.count))
    }
}

enum SecretKey {
    nonisolated static func setting(_ key: String) -> String {
        "settings.\(key)"
    }

    nonisolated static func debridToken(service: DebridServiceType, configId: String? = nil) -> String {
        if let configId {
            return "debrid.\(service.rawValue).\(configId)"
        }
        return "debrid.\(service.rawValue)"
    }
}
