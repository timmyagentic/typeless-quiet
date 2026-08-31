import Foundation
import Security

protocol AccountSecretStoring: Sendable {
    func containsSecret(accountID: UUID) throws -> Bool
    func readSecret(accountID: UUID) throws -> String?
    func saveSecret(_ secret: String, accountID: UUID) throws
    func deleteSecret(accountID: UUID) throws
}

struct AccountSecretStoreError: LocalizedError, Equatable {
    let operation: String
    let status: OSStatus

    var errorDescription: String? {
        let description = SecCopyErrorMessageString(status, nil) as String?
            ?? "OSStatus \(status)"
        return "Keychain \(operation) 失败：\(description)"
    }
}

struct KeychainAccountSecretStore: AccountSecretStoring {
    private let service: String

    init(
        service: String = ProcessInfo.processInfo.environment["TYPELESS_PLUSPLUS_KEYCHAIN_SERVICE"]
            ?? "io.github.timmyagentic.TypelessPlusPlus.account-secret"
    ) {
        self.service = service
    }

    func containsSecret(accountID: UUID) throws -> Bool {
        try readSecret(accountID: accountID) != nil
    }

    func readSecret(accountID: UUID) throws -> String? {
        var query = baseQuery(accountID: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              let secret = String(data: data, encoding: .utf8)
        else {
            throw AccountSecretStoreError(operation: "读取", status: status)
        }
        return secret
    }

    func saveSecret(_ secret: String, accountID: UUID) throws {
        if secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try deleteSecret(accountID: accountID)
            return
        }

        let query = baseQuery(accountID: accountID)
        let secretData = Data(secret.utf8)
        let attributes: [String: Any] = [kSecValueData as String: secretData]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AccountSecretStoreError(operation: "更新", status: updateStatus)
        }

        var create = query
        create[kSecValueData as String] = secretData
        create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let createStatus = SecItemAdd(create as CFDictionary, nil)
        guard createStatus == errSecSuccess else {
            throw AccountSecretStoreError(operation: "保存", status: createStatus)
        }
    }

    func deleteSecret(accountID: UUID) throws {
        let status = SecItemDelete(baseQuery(accountID: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccountSecretStoreError(operation: "删除", status: status)
        }
    }

    private func baseQuery(accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
        ]
    }
}
