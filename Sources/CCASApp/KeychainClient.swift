import Foundation
import Security

struct KeychainPasswordItem {
    var account: String
    var password: String
}

final class KeychainClient {
    func readGenericPasswordItem(service: String) throws -> KeychainPasswordItem? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw AccountSwitcherError.keychain(Self.message(for: status))
        }

        guard
            let item = result as? [String: Any],
            let data = item[kSecValueData as String] as? Data,
            let password = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let account = item[kSecAttrAccount as String] as? String
        return KeychainPasswordItem(account: account?.isEmpty == false ? account! : NSUserName(), password: password)
    }

    func readGenericPassword(service: String, account: String? = nil) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if let account {
            query[kSecAttrAccount as String] = account
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw AccountSwitcherError.keychain(Self.message(for: status))
        }

        guard let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func upsertGenericPassword(service: String, account: String, password: String) throws {
        guard let data = password.data(using: .utf8) else {
            throw AccountSwitcherError.keychain(L10n.string(.errorCredentialEncoding))
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let update: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw AccountSwitcherError.keychain(Self.message(for: updateStatus))
        }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AccountSwitcherError.keychain(Self.message(for: addStatus))
        }
    }

    func deleteGenericPassword(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }

        throw AccountSwitcherError.keychain(Self.message(for: status))
    }

    private static func message(for status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "OSStatus \(status)"
    }
}
