import Foundation
import Security

struct KeychainPasswordItem {
    var account: String
    var password: String
}

final class KeychainClient {
    private let logger = DebugLogger(category: "Keychain")

    func readGenericPasswordItem(service: String) throws -> KeychainPasswordItem? {
        logger.notice("read item service=\(service)")

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
            logger.notice("read item service=\(service) status=notFound")
            return nil
        }

        guard status == errSecSuccess else {
            logger.error("read item service=\(service) status=\(Int(status)) message=\(Self.message(for: status))")
            throw AccountSwitcherError.keychain(Self.message(for: status))
        }

        guard
            let item = result as? [String: Any],
            let data = item[kSecValueData as String] as? Data,
            let password = String(data: data, encoding: .utf8)
        else {
            logger.notice("read item service=\(service) status=success emptyResult=true")
            return nil
        }

        let account = item[kSecAttrAccount as String] as? String
        logger.notice("read item service=\(service) status=success hasAccount=\((account?.isEmpty == false))")
        return KeychainPasswordItem(account: account?.isEmpty == false ? account! : NSUserName(), password: password)
    }

    func readGenericPassword(service: String, account: String? = nil) throws -> String? {
        let hasAccountFilter = account != nil
        logger.notice("read password service=\(service) hasAccountFilter=\(hasAccountFilter)")

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
            logger.notice("read password service=\(service) hasAccountFilter=\(hasAccountFilter) status=notFound")
            return nil
        }

        guard status == errSecSuccess else {
            logger.error("read password service=\(service) hasAccountFilter=\(hasAccountFilter) status=\(Int(status)) message=\(Self.message(for: status))")
            throw AccountSwitcherError.keychain(Self.message(for: status))
        }

        guard let data = result as? Data else {
            logger.notice("read password service=\(service) hasAccountFilter=\(hasAccountFilter) status=success emptyResult=true")
            return nil
        }

        logger.notice("read password service=\(service) hasAccountFilter=\(hasAccountFilter) status=success")
        return String(data: data, encoding: .utf8)
    }

    func upsertGenericPassword(service: String, account: String, password: String) throws {
        logger.notice("upsert password service=\(service)")

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
            logger.notice("upsert password service=\(service) status=updated")
            return
        }

        guard updateStatus == errSecItemNotFound else {
            logger.error("upsert password service=\(service) updateStatus=\(Int(updateStatus)) message=\(Self.message(for: updateStatus))")
            throw AccountSwitcherError.keychain(Self.message(for: updateStatus))
        }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            logger.error("upsert password service=\(service) addStatus=\(Int(addStatus)) message=\(Self.message(for: addStatus))")
            throw AccountSwitcherError.keychain(Self.message(for: addStatus))
        }
        logger.notice("upsert password service=\(service) status=added")
    }

    func upsertGenericPasswordForService(service: String, fallbackAccount: String, password: String) throws {
        logger.notice("upsert password by service service=\(service) hasFallbackAccount=\((!fallbackAccount.isEmpty))")

        guard let data = password.data(using: .utf8) else {
            throw AccountSwitcherError.keychain(L10n.string(.errorCredentialEncoding))
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        let update: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            logger.notice("upsert password by service service=\(service) status=updated")
            return
        }

        guard updateStatus == errSecItemNotFound else {
            logger.error("upsert password by service service=\(service) updateStatus=\(Int(updateStatus)) message=\(Self.message(for: updateStatus))")
            throw AccountSwitcherError.keychain(Self.message(for: updateStatus))
        }

        var add = query
        add[kSecAttrAccount as String] = fallbackAccount
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            logger.error("upsert password by service service=\(service) hasFallbackAccount=\((!fallbackAccount.isEmpty)) addStatus=\(Int(addStatus)) message=\(Self.message(for: addStatus))")
            throw AccountSwitcherError.keychain(Self.message(for: addStatus))
        }

        logger.notice("upsert password by service service=\(service) status=added hasFallbackAccount=\((!fallbackAccount.isEmpty))")
    }

    func deleteGenericPassword(service: String, account: String) throws {
        logger.notice("delete password service=\(service)")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            logger.notice("delete password service=\(service) status=\(status == errSecSuccess ? "deleted" : "notFound")")
            return
        }

        logger.error("delete password service=\(service) status=\(Int(status)) message=\(Self.message(for: status))")
        throw AccountSwitcherError.keychain(Self.message(for: status))
    }

    private static func message(for status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "OSStatus \(status)"
    }
}
