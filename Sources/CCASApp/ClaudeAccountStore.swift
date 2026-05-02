import Darwin
import Foundation

final class ClaudeAccountStore {
    private let fileManager: FileManager
    private let keychain: KeychainClient
    private let home: URL

    private let claudeCredentialsService = "Claude Code-credentials"
    private let backupCredentialsService = "dev.local.ccas.accounts"

    init(
        fileManager: FileManager = .default,
        keychain: KeychainClient = KeychainClient(),
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.keychain = keychain
        self.home = home
    }

    var backupDirectory: URL {
        home.appendingPathComponent(".ccas", isDirectory: true)
    }

    private var sequenceFile: URL {
        backupDirectory.appendingPathComponent("sequence.json")
    }

    private var configsDirectory: URL {
        backupDirectory.appendingPathComponent("configs", isDirectory: true)
    }

    private var lockFile: URL {
        backupDirectory.appendingPathComponent(".lock")
    }

    func currentIdentity() throws -> AccountIdentity? {
        let configURL = claudeConfigURL()
        guard fileManager.fileExists(atPath: configURL.path) else {
            return nil
        }

        let config = try readJSONObject(configURL)
        guard let oauth = config["oauthAccount"] as? [String: Any] else {
            return nil
        }

        guard let email = oauth["emailAddress"] as? String, !email.isEmpty else {
            return nil
        }

        return AccountIdentity(
            email: email,
            accountUuid: oauth["accountUuid"] as? String ?? "",
            organizationUuid: oauth["organizationUuid"] as? String ?? "",
            organizationName: oauth["organizationName"] as? String ?? ""
        )
    }

    func listAccounts() throws -> [ManagedAccount] {
        try migrateOrganizationFieldsIfNeeded()

        guard let data = try readSequenceIfPresent() else {
            return []
        }

        let identity = try currentIdentity()

        return data.sequence.compactMap { number in
            guard let record = data.accounts[String(number)] else {
                return nil
            }

            let isActive: Bool
            if let identity {
                isActive = record.email == identity.email
                    && record.organizationUuid == identity.organizationUuid
            } else {
                isActive = data.activeAccountNumber == number
            }

            return ManagedAccount(number: number, record: record, isActive: isActive)
        }
    }

    @discardableResult
    func addCurrentAccount() throws -> AddAccountResult {
        try setupDirectories()
        try initializeSequenceFileIfNeeded()
        try migrateOrganizationFieldsIfNeeded()

        guard let identity = try currentIdentity() else {
            throw AccountSwitcherError.noActiveClaudeAccount
        }

        let currentCredentials = try readCurrentCredentials() ?? ""
        guard !currentCredentials.isEmpty else {
            throw AccountSwitcherError.noClaudeCredentials
        }

        let configURL = claudeConfigURL()
        guard fileManager.fileExists(atPath: configURL.path) else {
            throw AccountSwitcherError.claudeConfigNotFound
        }

        let currentConfig = try String(contentsOf: configURL, encoding: .utf8)
        var data = try readSequence()

        if let existing = data.accounts.first(where: { _, account in
            account.email == identity.email
                && account.organizationUuid == identity.organizationUuid
        }) {
            let number = existing.key
            var record = existing.value
            record.uuid = identity.accountUuid
            record.organizationName = identity.organizationName
            record.organizationUuid = identity.organizationUuid

            try writeAccountCredentials(number: number, email: identity.email, credentials: currentCredentials)
            try writeAccountConfig(number: number, email: identity.email, config: currentConfig)

            data.accounts[number] = record
            data.activeAccountNumber = Int(number)
            data.lastUpdated = Timestamp.now()
            try writeSequence(data)

            return .updated(ManagedAccount(number: Int(number) ?? 0, record: record, isActive: true))
        }

        let nextNumber = nextAccountNumber(in: data)
        let record = AccountRecord(
            email: identity.email,
            uuid: identity.accountUuid,
            organizationUuid: identity.organizationUuid,
            organizationName: identity.organizationName,
            added: Timestamp.now()
        )

        try writeAccountCredentials(number: String(nextNumber), email: identity.email, credentials: currentCredentials)
        try writeAccountConfig(number: String(nextNumber), email: identity.email, config: currentConfig)

        data.accounts[String(nextNumber)] = record
        data.sequence.append(nextNumber)
        data.activeAccountNumber = nextNumber
        data.lastUpdated = Timestamp.now()
        try writeSequence(data)

        return .added(ManagedAccount(number: nextNumber, record: record, isActive: true))
    }

    func switchToAccount(number: Int) throws {
        try setupDirectories()
        try migrateOrganizationFieldsIfNeeded()

        guard try readSequenceIfPresent() != nil else {
            throw AccountSwitcherError.noManagedAccounts
        }

        try FileLock(path: lockFile).withExclusiveLock {
            var data = try readSequence()

            guard let target = data.accounts[String(number)] else {
                throw AccountSwitcherError.accountNotFound(number)
            }

            guard let currentIdentity = try currentIdentity() else {
                throw AccountSwitcherError.noActiveClaudeAccount
            }

            guard let currentNumber = managedNumber(for: currentIdentity, in: data) else {
                throw AccountSwitcherError.accountNotManaged(currentIdentity.email)
            }

            let configURL = claudeConfigURL()
            guard fileManager.fileExists(atPath: configURL.path) else {
                throw AccountSwitcherError.claudeConfigNotFound
            }

            let originalCredentials = try readCurrentCredentials() ?? ""
            guard !originalCredentials.isEmpty else {
                throw AccountSwitcherError.noClaudeCredentials
            }
            let originalConfig = try String(contentsOf: configURL, encoding: .utf8)

            var wroteCredentials = false
            var wroteConfig = false

            do {
                try writeAccountCredentials(
                    number: String(currentNumber),
                    email: currentIdentity.email,
                    credentials: originalCredentials
                )
                try writeAccountConfig(
                    number: String(currentNumber),
                    email: currentIdentity.email,
                    config: originalConfig
                )

                let targetCredentials = try readAccountCredentials(number: String(number), email: target.email)
                let targetConfig = try readAccountConfig(number: String(number), email: target.email)
                guard !targetCredentials.isEmpty, !targetConfig.isEmpty else {
                    throw AccountSwitcherError.missingBackupData(number)
                }

                try writeCurrentCredentials(targetCredentials)
                wroteCredentials = true

                let targetConfigJSON = try parseJSONObject(from: targetConfig, source: configURL)
                guard let targetOAuth = targetConfigJSON["oauthAccount"] as? [String: Any] else {
                    throw AccountSwitcherError.invalidBackupConfig(number)
                }

                var currentConfigJSON = try readJSONObject(configURL)
                currentConfigJSON["oauthAccount"] = targetOAuth
                try writeJSONObject(currentConfigJSON, to: configURL)
                wroteConfig = true

                data.activeAccountNumber = number
                data.lastUpdated = Timestamp.now()
                try writeSequence(data)
            } catch {
                if wroteCredentials {
                    try? writeCurrentCredentials(originalCredentials)
                }
                if wroteConfig {
                    try? originalConfig.write(to: configURL, atomically: true, encoding: .utf8)
                    chmod(configURL.path, S_IRUSR | S_IWUSR)
                }
                throw error
            }
        }
    }

    private func setupDirectories() throws {
        for directory in [backupDirectory, configsDirectory] {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            chmod(directory.path, S_IRWXU)
        }
    }

    private func initializeSequenceFileIfNeeded() throws {
        if !fileManager.fileExists(atPath: sequenceFile.path) {
            try writeSequence(.empty())
        }
    }

    private func claudeConfigURL() -> URL {
        let primary = home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent(".claude.json")
        let fallback = home.appendingPathComponent(".claude.json")

        let candidates = [primary, fallback].filter { url in
            guard fileManager.fileExists(atPath: url.path) else {
                return false
            }
            guard let object = try? readJSONObject(url) else {
                return false
            }
            return object["oauthAccount"] != nil
        }

        if candidates.isEmpty {
            return fallback
        }

        if candidates.count == 1 {
            return candidates[0]
        }

        return candidates.max { lhs, rhs in
            modificationDate(for: lhs) < modificationDate(for: rhs)
        } ?? fallback
    }

    private func modificationDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private func readCurrentCredentials() throws -> String? {
        try keychain.readGenericPasswordItem(service: claudeCredentialsService)?.password
    }

    private func writeCurrentCredentials(_ credentials: String) throws {
        let existing = try keychain.readGenericPasswordItem(service: claudeCredentialsService)
        let account = existing?.account.isEmpty == false ? existing!.account : NSUserName()
        try keychain.upsertGenericPassword(
            service: claudeCredentialsService,
            account: account.isEmpty ? "user" : account,
            password: credentials
        )
    }

    private func backupCredentialAccount(number: String, email: String) -> String {
        "account-\(number)-\(email)"
    }

    private func readAccountCredentials(number: String, email: String) throws -> String {
        try keychain.readGenericPassword(
            service: backupCredentialsService,
            account: backupCredentialAccount(number: number, email: email)
        ) ?? ""
    }

    private func writeAccountCredentials(number: String, email: String, credentials: String) throws {
        try keychain.upsertGenericPassword(
            service: backupCredentialsService,
            account: backupCredentialAccount(number: number, email: email),
            password: credentials
        )
    }

    private func accountConfigURL(number: String, email: String) -> URL {
        configsDirectory.appendingPathComponent(".claude-config-\(number)-\(email).json")
    }

    private func readAccountConfig(number: String, email: String) throws -> String {
        let url = accountConfigURL(number: number, email: email)
        guard fileManager.fileExists(atPath: url.path) else {
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func writeAccountConfig(number: String, email: String, config: String) throws {
        let url = accountConfigURL(number: number, email: email)
        try config.write(to: url, atomically: true, encoding: .utf8)
        chmod(url.path, S_IRUSR | S_IWUSR)
    }

    private func readSequenceIfPresent() throws -> SequenceData? {
        guard fileManager.fileExists(atPath: sequenceFile.path) else {
            return nil
        }
        return try readSequence()
    }

    private func readSequence() throws -> SequenceData {
        guard fileManager.fileExists(atPath: sequenceFile.path) else {
            throw AccountSwitcherError.noManagedAccounts
        }

        do {
            let data = try Data(contentsOf: sequenceFile)
            return try JSONDecoder().decode(SequenceData.self, from: data)
        } catch {
            throw AccountSwitcherError.fileSystem(L10n.string(.errorReadSequence, error.localizedDescription))
        }
    }

    private func writeSequence(_ data: SequenceData) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(data)
        try setupParentDirectory(for: sequenceFile)
        try json.write(to: sequenceFile, options: .atomic)
        chmod(sequenceFile.path, S_IRUSR | S_IWUSR)
    }

    private func readJSONObject(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try parseJSONObject(from: data, source: url)
    }

    private func parseJSONObject(from string: String, source: URL) throws -> [String: Any] {
        guard let data = string.data(using: .utf8) else {
            throw AccountSwitcherError.invalidClaudeConfig(source)
        }
        return try parseJSONObject(from: data, source: source)
    }

    private func parseJSONObject(from data: Data, source: URL) throws -> [String: Any] {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AccountSwitcherError.invalidClaudeConfig(source)
            }
            return object
        } catch let error as AccountSwitcherError {
            throw error
        } catch {
            throw AccountSwitcherError.invalidClaudeConfig(source)
        }
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw AccountSwitcherError.invalidClaudeConfig(url)
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try setupParentDirectory(for: url)
        try data.write(to: url, options: .atomic)
        chmod(url.path, S_IRUSR | S_IWUSR)
    }

    private func setupParentDirectory(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }

    private func nextAccountNumber(in data: SequenceData) -> Int {
        let existing = data.accounts.keys.compactMap(Int.init)
        return (existing.max() ?? 0) + 1
    }

    private func managedNumber(for identity: AccountIdentity, in data: SequenceData) -> Int? {
        data.accounts.first { _, record in
            record.email == identity.email
                && record.organizationUuid == identity.organizationUuid
        }.flatMap { Int($0.key) }
    }

    private func migrateOrganizationFieldsIfNeeded() throws {
        guard var data = try readSequenceIfPresent() else {
            return
        }

        let needsMigration = data.accounts.values.contains { !$0.hasOrganizationFields }

        guard needsMigration else {
            return
        }

        let liveIdentity = try? currentIdentity()
        var updated = false

        for (number, var record) in data.accounts {
            if record.email == liveIdentity?.email {
                record.organizationUuid = liveIdentity?.organizationUuid ?? ""
                record.organizationName = liveIdentity?.organizationName ?? ""
                record.hasOrganizationFields = true
                data.accounts[number] = record
                updated = true
                continue
            }

            let config = try? readAccountConfig(number: number, email: record.email)
            if let config,
               let object = try? parseJSONObject(from: config, source: accountConfigURL(number: number, email: record.email)),
               let oauth = object["oauthAccount"] as? [String: Any] {
                record.organizationUuid = oauth["organizationUuid"] as? String ?? ""
                record.organizationName = oauth["organizationName"] as? String ?? ""
                record.hasOrganizationFields = true
                data.accounts[number] = record
                updated = true
            } else {
                record.hasOrganizationFields = true
                data.accounts[number] = record
                updated = true
            }
        }

        if updated {
            data.lastUpdated = Timestamp.now()
            try writeSequence(data)
        }
    }
}
