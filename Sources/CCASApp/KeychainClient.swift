import Foundation
import OSLog
import Security

struct KeychainPasswordItem {
    var account: String
    var password: String
}

final class KeychainClient {
    private let logger = Logger(subsystem: "dev.local.ccas", category: "Keychain")

    func readGenericPasswordItem(service: String) throws -> KeychainPasswordItem? {
        logger.notice("read item service=\(service, privacy: .public)")

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
            logger.notice("read item service=\(service, privacy: .public) status=notFound")
            return nil
        }

        guard status == errSecSuccess else {
            logger.error("read item service=\(service, privacy: .public) status=\(Int(status), privacy: .public) message=\(Self.message(for: status), privacy: .public)")
            throw AccountSwitcherError.keychain(Self.message(for: status))
        }

        guard
            let item = result as? [String: Any],
            let data = item[kSecValueData as String] as? Data,
            let password = String(data: data, encoding: .utf8)
        else {
            logger.notice("read item service=\(service, privacy: .public) status=success emptyResult=true")
            return nil
        }

        let account = item[kSecAttrAccount as String] as? String
        logger.notice("read item service=\(service, privacy: .public) status=success account=\((account ?? "<empty>"), privacy: .public)")
        return KeychainPasswordItem(account: account?.isEmpty == false ? account! : NSUserName(), password: password)
    }

    func readGenericPassword(service: String, account: String? = nil) throws -> String? {
        let accountLabel = account ?? "<any>"
        logger.notice("read password service=\(service, privacy: .public) account=\(accountLabel, privacy: .public)")

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
            logger.notice("read password service=\(service, privacy: .public) account=\(accountLabel, privacy: .public) status=notFound")
            return nil
        }

        guard status == errSecSuccess else {
            logger.error("read password service=\(service, privacy: .public) account=\(accountLabel, privacy: .public) status=\(Int(status), privacy: .public) message=\(Self.message(for: status), privacy: .public)")
            throw AccountSwitcherError.keychain(Self.message(for: status))
        }

        guard let data = result as? Data else {
            logger.notice("read password service=\(service, privacy: .public) account=\(accountLabel, privacy: .public) status=success emptyResult=true")
            return nil
        }

        logger.notice("read password service=\(service, privacy: .public) account=\(accountLabel, privacy: .public) status=success")
        return String(data: data, encoding: .utf8)
    }

    func upsertGenericPassword(service: String, account: String, password: String) throws {
        logger.notice("upsert password service=\(service, privacy: .public) account=\(account, privacy: .public)")

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
            logger.notice("upsert password service=\(service, privacy: .public) account=\(account, privacy: .public) status=updated")
            return
        }

        guard updateStatus == errSecItemNotFound else {
            logger.error("upsert password service=\(service, privacy: .public) account=\(account, privacy: .public) updateStatus=\(Int(updateStatus), privacy: .public) message=\(Self.message(for: updateStatus), privacy: .public)")
            throw AccountSwitcherError.keychain(Self.message(for: updateStatus))
        }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            logger.error("upsert password service=\(service, privacy: .public) account=\(account, privacy: .public) addStatus=\(Int(addStatus), privacy: .public) message=\(Self.message(for: addStatus), privacy: .public)")
            throw AccountSwitcherError.keychain(Self.message(for: addStatus))
        }
        logger.notice("upsert password service=\(service, privacy: .public) account=\(account, privacy: .public) status=added")
    }

    func upsertGenericPasswordForService(service: String, fallbackAccount: String, password: String) throws {
        logger.notice("upsert password by service service=\(service, privacy: .public) fallbackAccount=\(fallbackAccount, privacy: .public)")

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
            logger.notice("upsert password by service service=\(service, privacy: .public) status=updated")
            return
        }

        guard updateStatus == errSecItemNotFound else {
            logger.error("upsert password by service service=\(service, privacy: .public) updateStatus=\(Int(updateStatus), privacy: .public) message=\(Self.message(for: updateStatus), privacy: .public)")
            throw AccountSwitcherError.keychain(Self.message(for: updateStatus))
        }

        var add = query
        add[kSecAttrAccount as String] = fallbackAccount
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            logger.error("upsert password by service service=\(service, privacy: .public) fallbackAccount=\(fallbackAccount, privacy: .public) addStatus=\(Int(addStatus), privacy: .public) message=\(Self.message(for: addStatus), privacy: .public)")
            throw AccountSwitcherError.keychain(Self.message(for: addStatus))
        }

        logger.notice("upsert password by service service=\(service, privacy: .public) status=added fallbackAccount=\(fallbackAccount, privacy: .public)")
    }

    func deleteGenericPassword(service: String, account: String) throws {
        logger.notice("delete password service=\(service, privacy: .public) account=\(account, privacy: .public)")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            logger.notice("delete password service=\(service, privacy: .public) account=\(account, privacy: .public) status=\(status == errSecSuccess ? "deleted" : "notFound", privacy: .public)")
            return
        }

        logger.error("delete password service=\(service, privacy: .public) account=\(account, privacy: .public) status=\(Int(status), privacy: .public) message=\(Self.message(for: status), privacy: .public)")
        throw AccountSwitcherError.keychain(Self.message(for: status))
    }

    private static func message(for status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "OSStatus \(status)"
    }
}
