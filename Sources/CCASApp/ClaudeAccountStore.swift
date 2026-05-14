import Darwin
import Foundation

@MainActor
final class ClaudeAccountStore {
    private let fileManager: FileManager
    private let keychain: KeychainClient
    private let home: URL
    private let logger = DebugLogger(category: "AccountStore")

    private let claudeCredentialsService = "Claude Code-credentials"
    private let backupCredentialsService = "li.luy.ccas.accounts"
    private let anthropicAPIBaseURL = URL(string: "https://api.anthropic.com")!
    private let anthropicOAuthTokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private let anthropicOAuthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let anthropicOAuthBeta = "oauth-2025-04-20"
    private let claudeAIProfileScope = "user:profile"
    private let claudeAIInferenceScope = "user:inference"

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

    private var quotaCacheFile: URL {
        backupDirectory.appendingPathComponent("quota-cache.json")
    }

    func currentIdentity() throws -> AccountIdentity? {
        let configURL = claudeConfigURL()
        logger.notice("current identity read config")
        guard fileManager.fileExists(atPath: configURL.path) else {
            logger.notice("current identity configMissing")
            return nil
        }

        let config = try readJSONObject(configURL)
        guard let oauth = config["oauthAccount"] as? [String: Any] else {
            logger.notice("current identity missingOAuth")
            return nil
        }

        guard let email = oauth["emailAddress"] as? String, !email.isEmpty else {
            logger.notice("current identity missingEmail")
            return nil
        }

        logger.notice("current identity found hasEmail=\((!email.isEmpty))")

        return AccountIdentity(
            email: email,
            accountUuid: oauth["accountUuid"] as? String ?? "",
            organizationUuid: oauth["organizationUuid"] as? String ?? "",
            organizationName: oauth["organizationName"] as? String ?? ""
        )
    }

    func listAccounts() throws -> [ManagedAccount] {
        logger.notice("list accounts start")
        try migrateOrganizationFieldsIfNeeded()

        guard let data = try readSequenceIfPresent() else {
            logger.notice("list accounts noSequence")
            return []
        }

        let identity = try currentIdentity()

        let accounts: [ManagedAccount] = data.sequence.compactMap { number in
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

        logger.notice("list accounts done count=\(accounts.count) activeNumber=\((data.activeAccountNumber.map(String.init) ?? "<none>"))")
        return accounts
    }

    @discardableResult
    func addCurrentAccount() throws -> AddAccountResult {
        logger.notice("add current account start")
        try setupDirectories()
        try initializeSequenceFileIfNeeded()
        try migrateOrganizationFieldsIfNeeded()

        guard let identity = try currentIdentity() else {
            logger.error("add current account failed noActiveClaudeAccount")
            throw AccountSwitcherError.noActiveClaudeAccount
        }
        logger.notice("add current account identity found")

        let currentCredentials = try readCurrentCredentials() ?? ""
        guard !currentCredentials.isEmpty else {
            logger.error("add current account failed noClaudeCredentials")
            throw AccountSwitcherError.noClaudeCredentials
        }
        logger.notice("add current account currentCredentials=present")

        let configURL = claudeConfigURL()
        guard fileManager.fileExists(atPath: configURL.path) else {
            logger.error("add current account failed configMissing")
            throw AccountSwitcherError.claudeConfigNotFound
        }

        let currentConfig = try String(contentsOf: configURL, encoding: .utf8)
        var data = try readSequence()
        logger.notice("add current account sequenceLoaded count=\(data.accounts.count)")

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

            logger.notice("add current account updated number=\(number)")
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

        logger.notice("add current account added number=\(nextNumber)")
        return .added(ManagedAccount(number: nextNumber, record: record, isActive: true))
    }

    func switchToAccount(number: Int) throws {
        logger.notice("switch account start targetNumber=\(number)")

        do {
            try setupDirectories()
            try migrateOrganizationFieldsIfNeeded()

            guard try readSequenceIfPresent() != nil else {
                logger.error("switch account failed noManagedAccounts targetNumber=\(number)")
                throw AccountSwitcherError.noManagedAccounts
            }

            try FileLock(path: lockFile).withExclusiveLock {
                logger.notice("switch account lockAcquired targetNumber=\(number)")

                var data = try readSequence()
                logger.notice("switch account sequenceLoaded accountCount=\(data.accounts.count) activeNumber=\((data.activeAccountNumber.map(String.init) ?? "<none>"))")

                guard let target = data.accounts[String(number)] else {
                    logger.error("switch account failed accountNotFound targetNumber=\(number)")
                    throw AccountSwitcherError.accountNotFound(number)
                }
                logger.notice("switch account target found targetNumber=\(number)")

                guard let currentIdentity = try currentIdentity() else {
                    logger.error("switch account failed noActiveClaudeAccount targetNumber=\(number)")
                    throw AccountSwitcherError.noActiveClaudeAccount
                }
                logger.notice("switch account current identity found")

                guard let currentNumber = managedNumber(for: currentIdentity, in: data) else {
                    logger.error("switch account failed currentNotManaged")
                    throw AccountSwitcherError.accountNotManaged(currentIdentity.email)
                }
                logger.notice("switch account currentNumber=\(currentNumber)")

                let configURL = claudeConfigURL()
                guard fileManager.fileExists(atPath: configURL.path) else {
                    logger.error("switch account failed configMissing")
                    throw AccountSwitcherError.claudeConfigNotFound
                }
                logger.notice("switch account configFound")

                let originalConfig = try String(contentsOf: configURL, encoding: .utf8)
                logger.notice("switch account originalConfigLoaded bytes=\(originalConfig.utf8.count)")

                var rollbackCredentials = try readAccountCredentials(
                    number: String(currentNumber),
                    email: currentIdentity.email
                )
                if rollbackCredentials.isEmpty {
                    logger.notice("switch account missingRollbackCredentials attemptingRepair currentNumber=\(currentNumber)")
                    rollbackCredentials = try readCurrentCredentials() ?? ""

                    guard !rollbackCredentials.isEmpty else {
                        logger.error("switch account failed missingRollbackCredentials repairEmpty currentNumber=\(currentNumber)")
                        throw AccountSwitcherError.missingCredentials(currentNumber, currentIdentity.email)
                    }

                    try writeAccountCredentials(
                        number: String(currentNumber),
                        email: currentIdentity.email,
                        credentials: rollbackCredentials
                    )
                    logger.notice("switch account rollbackCredentialsRepaired currentNumber=\(currentNumber)")
                }
                logger.notice("switch account rollbackCredentials=present currentNumber=\(currentNumber)")

                var wroteCredentials = false
                var wroteConfig = false

                do {
                    try writeAccountConfig(
                        number: String(currentNumber),
                        email: currentIdentity.email,
                        config: originalConfig
                    )
                    logger.notice("switch account currentConfigBackedUp currentNumber=\(currentNumber)")

                    let targetCredentials = try readAccountCredentials(number: String(number), email: target.email)
                    let targetConfig = try readAccountConfig(number: String(number), email: target.email)
                    logger.notice("switch account targetBackupsLoaded credentialsPresent=\((!targetCredentials.isEmpty)) configBytes=\(targetConfig.utf8.count)")
                    guard !targetConfig.isEmpty else {
                        logger.error("switch account failed missingTargetConfig targetNumber=\(number)")
                        throw AccountSwitcherError.missingBackupData(number)
                    }
                    guard !targetCredentials.isEmpty else {
                        logger.error("switch account failed missingTargetCredentials targetNumber=\(number)")
                        throw AccountSwitcherError.missingCredentials(number, target.email)
                    }

                    logger.notice("switch account writeCurrentCredentials start targetNumber=\(number)")
                    try writeCurrentCredentials(targetCredentials)
                    wroteCredentials = true
                    logger.notice("switch account writeCurrentCredentials done targetNumber=\(number)")

                    let targetConfigJSON = try parseJSONObject(from: targetConfig, source: configURL)
                    guard let targetOAuth = targetConfigJSON["oauthAccount"] as? [String: Any] else {
                        logger.error("switch account failed invalidTargetOAuth targetNumber=\(number)")
                        throw AccountSwitcherError.invalidBackupConfig(number)
                    }

                    var currentConfigJSON = try readJSONObject(configURL)
                    currentConfigJSON["oauthAccount"] = targetOAuth
                    try writeJSONObject(currentConfigJSON, to: configURL)
                    wroteConfig = true
                    logger.notice("switch account configWritten targetNumber=\(number)")

                    data.activeAccountNumber = number
                    data.lastUpdated = Timestamp.now()
                    try writeSequence(data)
                    logger.notice("switch account done targetNumber=\(number)")
                } catch {
                    logger.error("switch account innerFailure targetNumber=\(number) wroteCredentials=\(wroteCredentials) wroteConfig=\(wroteConfig) errorType=\(String(describing: type(of: error)))")
                    if wroteCredentials {
                        do {
                            try writeCurrentCredentials(rollbackCredentials)
                            logger.notice("switch account rollbackCredentialsRestored currentNumber=\(currentNumber)")
                        } catch {
                            logger.error("switch account rollbackCredentialsFailed currentNumber=\(currentNumber) errorType=\(String(describing: type(of: error)))")
                        }
                    }
                    if wroteConfig {
                        do {
                            try originalConfig.write(to: configURL, atomically: true, encoding: .utf8)
                            chmod(configURL.path, S_IRUSR | S_IWUSR)
                            logger.notice("switch account rollbackConfigRestored")
                        } catch {
                            logger.error("switch account rollbackConfigFailed errorType=\(String(describing: type(of: error)))")
                        }
                    }
                    throw error
                }
            }
        } catch {
            logger.error("switch account failed targetNumber=\(number) errorType=\(String(describing: type(of: error)))")
            throw error
        }
    }

    func usageInfo(for account: ManagedAccount) async throws -> AccountQuotaInfo {
        logger.notice("usage info start number=\(account.number)")
        let number = String(account.number)
        let credentials = try readAccountCredentials(number: number, email: account.record.email)
        guard !credentials.isEmpty else {
            throw AccountSwitcherError.missingCredentials(account.number, account.record.email)
        }

        var parsed = try parseClaudeCredentials(credentials)
        logger.notice("usage info credentialsParsed number=\(account.number) scopes=\(parsed.oauth.scopes.count) hasRefreshToken=\(parsed.oauth.refreshToken?.isEmpty == false) isExpiringSoon=\(parsed.oauth.isExpiringSoon)")
        guard parsed.oauth.scopes.contains(claudeAIProfileScope) else {
            logger.notice("usage info unavailable missingProfileScope number=\(account.number)")
            return .unavailable(L10n.string(.quotaUnavailable))
        }

        if parsed.oauth.isExpiringSoon {
            logger.notice("usage info refreshingExpiringToken number=\(account.number)")
            try await refreshAndStoreOAuthCredentials(&parsed, for: account)
            logger.notice("usage info tokenRefreshed number=\(account.number)")
        }

        logger.notice("usage info fetchingUsage number=\(account.number)")

        do {
            let object = try await fetchUsageObject(accessToken: parsed.oauth.accessToken)
            let info = usageInfo(from: object, plan: parsed.oauth.plan)
            logger.notice("usage info done number=\(account.number)")
            return info
        } catch QuotaFetchError.unauthorized {
            logger.notice("usage info unauthorized refreshing number=\(account.number)")
            try await refreshAndStoreOAuthCredentials(&parsed, for: account)
            let object = try await fetchUsageObject(accessToken: parsed.oauth.accessToken)
            let info = usageInfo(from: object, plan: parsed.oauth.plan)
            logger.notice("usage info done afterRefresh number=\(account.number)")
            return info
        }
    }

    func cachedQuotaSnapshot() -> AccountQuotaCacheSnapshot? {
        guard fileManager.fileExists(atPath: quotaCacheFile.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: quotaCacheFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(AccountQuotaCacheSnapshot.self, from: data)
            logger.notice("quota cache read entries=\(snapshot.entries.count)")
            return snapshot
        } catch {
            logger.error("quota cache read failed errorType=\(String(describing: type(of: error)))")
            return nil
        }
    }

    func writeQuotaSnapshot(_ snapshot: AccountQuotaCacheSnapshot) {
        do {
            try setupDirectories()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: quotaCacheFile, options: .atomic)
            chmod(quotaCacheFile.path, S_IRUSR | S_IWUSR)
            logger.notice("quota cache wrote entries=\(snapshot.entries.count)")
        } catch {
            logger.error("quota cache write failed errorType=\(String(describing: type(of: error)))")
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
        logger.notice("read current Claude Code credentials service=\(self.claudeCredentialsService)")
        return try keychain.readGenericPasswordItem(service: claudeCredentialsService)?.password
    }

    private func writeCurrentCredentials(_ credentials: String) throws {
        let fallbackAccount = NSUserName().isEmpty ? "user" : NSUserName()
        logger.notice("write current Claude Code credentials service=\(self.claudeCredentialsService) hasFallbackAccount=\((!fallbackAccount.isEmpty))")
        try keychain.upsertGenericPasswordForService(
            service: claudeCredentialsService,
            fallbackAccount: fallbackAccount,
            password: credentials
        )
    }

    private func backupCredentialAccount(number: String, email: String) -> String {
        "account-\(number)-\(email)"
    }

    private func readAccountCredentials(number: String, email: String) throws -> String {
        logger.notice("read backup credentials number=\(number) service=\(self.backupCredentialsService)")
        return try keychain.readGenericPassword(
            service: backupCredentialsService,
            account: backupCredentialAccount(number: number, email: email)
        ) ?? ""
    }

    private func writeAccountCredentials(number: String, email: String, credentials: String) throws {
        logger.notice("write backup credentials number=\(number) service=\(self.backupCredentialsService)")
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
            logger.notice("read backup config missing number=\(number)")
            return ""
        }
        logger.notice("read backup config number=\(number)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func writeAccountConfig(number: String, email: String, config: String) throws {
        let url = accountConfigURL(number: number, email: email)
        logger.notice("write backup config number=\(number) bytes=\(config.utf8.count)")
        try config.write(to: url, atomically: true, encoding: .utf8)
        chmod(url.path, S_IRUSR | S_IWUSR)
    }

    private func readSequenceIfPresent() throws -> SequenceData? {
        guard fileManager.fileExists(atPath: sequenceFile.path) else {
            logger.notice("read sequence missing")
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
            let sequence = try JSONDecoder().decode(SequenceData.self, from: data)
            logger.notice("read sequence accountCount=\(sequence.accounts.count)")
            return sequence
        } catch {
            logger.error("read sequence failed errorType=\(String(describing: type(of: error)))")
            throw AccountSwitcherError.fileSystem(L10n.string(.errorReadSequence, error.localizedDescription))
        }
    }

    private func writeSequence(_ data: SequenceData) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(data)
        try setupParentDirectory(for: sequenceFile)
        logger.notice("write sequence accountCount=\(data.accounts.count) activeNumber=\((data.activeAccountNumber.map(String.init) ?? "<none>"))")
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

    private func parseClaudeCredentials(_ credentials: String) throws -> ParsedClaudeCredentials {
        guard let data = credentials.data(using: .utf8) else {
            logger.error("parse credentials failed reason=utf8EncodeFailed length=\(credentials.count)")
            throw QuotaFetchError.invalidCredentials
        }

        let rootObject: Any
        do {
            rootObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            let preview = String(credentials.prefix(256))
            logger.error("parse credentials failed reason=jsonParseFailed:\(error.localizedDescription) length=\(credentials.count) preview=\(preview)")
            throw error
        }

        guard let root = rootObject as? [String: Any] else {
            logger.error("parse credentials failed reason=notDictionary:\(type(of: rootObject))")
            throw QuotaFetchError.invalidCredentials
        }

        let oauthKey: String?
        let oauthObject: [String: Any]
        if let nested = root["claudeAiOauth"] as? [String: Any] {
            oauthKey = "claudeAiOauth"
            oauthObject = nested
        } else if root["accessToken"] != nil || root["access_token"] != nil {
            oauthKey = nil
            oauthObject = root
        } else {
            throw QuotaFetchError.missingOAuth
        }

        let oauth = try ClaudeOAuthCredentials(object: oauthObject)
        return ParsedClaudeCredentials(root: root, oauthKey: oauthKey, oauthObject: oauthObject, oauth: oauth)
    }

    private func encodedCredentials(from parsed: ParsedClaudeCredentials) throws -> String {
        var root = parsed.root
        if let oauthKey = parsed.oauthKey {
            root[oauthKey] = parsed.oauthObject
        } else {
            root = parsed.oauthObject
        }

        guard JSONSerialization.isValidJSONObject(root) else {
            throw QuotaFetchError.invalidCredentials
        }

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw QuotaFetchError.invalidCredentials
        }
        return string
    }

    private func refreshAndStoreOAuthCredentials(_ parsed: inout ParsedClaudeCredentials, for account: ManagedAccount) async throws {
        try await refreshOAuthCredentials(&parsed)
        let updatedCredentials = try encodedCredentials(from: parsed)
        try writeAccountCredentials(number: String(account.number), email: account.record.email, credentials: updatedCredentials)
        if account.isActive {
            try writeCurrentCredentials(updatedCredentials)
        }
    }

    private func refreshOAuthCredentials(_ parsed: inout ParsedClaudeCredentials) async throws {
        guard let refreshToken = parsed.oauth.refreshToken, !refreshToken.isEmpty else {
            throw QuotaFetchError.missingRefreshToken
        }

        var request = URLRequest(url: anthropicOAuthTokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let scopes = parsed.oauth.scopes.isEmpty
            ? [claudeAIProfileScope, claudeAIInferenceScope, "user:sessions:claude_code", "user:mcp_servers", "user:file_upload"]
            : parsed.oauth.scopes
        let clientID = parsed.oauth.clientID?.isEmpty == false ? parsed.oauth.clientID! : anthropicOAuthClientID
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "scope": scopes.joined(separator: " ")
        ]
        request.httpBody = formURLEncoded(body).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            logger.error("oauth refresh response notHTTP")
            throw QuotaFetchError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            logUsageResponseDiagnostics(http: http, data: data, reason: "oauthRefreshHttpStatus")
            throw QuotaFetchError.httpStatus(http.statusCode, errorMessage(from: data))
        }

        let refreshObject: Any
        do {
            refreshObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            logUsageResponseDiagnostics(http: http, data: data, reason: "oauthRefreshJsonParseFailed:\(error.localizedDescription)")
            throw error
        }

        guard let object = refreshObject as? [String: Any],
              let accessToken = stringValue(object["access_token"]),
              !accessToken.isEmpty
        else {
            logUsageResponseDiagnostics(http: http, data: data, reason: "oauthRefreshMissingAccessToken type=\(type(of: refreshObject))")
            throw QuotaFetchError.invalidResponse
        }

        let newRefreshToken = stringValue(object["refresh_token"]) ?? refreshToken
        let expiresIn = numberValue(object["expires_in"]) ?? 3600
        let expiresAt = Date().addingTimeInterval(expiresIn).timeIntervalSince1970 * 1000
        let responseScopes = scopesValue(object["scope"]) ?? scopes

        parsed.oauth.accessToken = accessToken
        parsed.oauth.refreshToken = newRefreshToken
        parsed.oauth.expiresAt = expiresAt
        parsed.oauth.scopes = responseScopes
        parsed.oauth.clientID = clientID

        parsed.oauthObject["accessToken"] = accessToken
        parsed.oauthObject["refreshToken"] = newRefreshToken
        parsed.oauthObject["expiresAt"] = expiresAt
        parsed.oauthObject["scopes"] = responseScopes
        parsed.oauthObject["clientId"] = clientID
    }

    private func fetchUsageObject(accessToken: String) async throws -> [String: Any] {
        var request = URLRequest(url: anthropicAPIBaseURL.appendingPathComponent("api/oauth/usage"))
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(anthropicOAuthBeta, forHTTPHeaderField: "anthropic-beta")
        request.setValue("CCAS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaFetchError.invalidResponse
        }

        if http.statusCode == 401 {
            throw QuotaFetchError.unauthorized
        }

        if http.statusCode == 429 {
            let retryAfter = retryAfterDate(from: http) ?? Date().addingTimeInterval(60)
            logUsageResponseDiagnostics(http: http, data: data, reason: "usageRateLimited retryAfterSec=\(Int(retryAfter.timeIntervalSinceNow.rounded()))")
            throw QuotaFetchError.rateLimited(retryAfter: retryAfter, message: errorMessage(from: data))
        }

        guard (200..<300).contains(http.statusCode) else {
            logUsageResponseDiagnostics(http: http, data: data, reason: "usageHttpStatus")
            throw QuotaFetchError.httpStatus(http.statusCode, errorMessage(from: data))
        }

        guard !data.isEmpty else {
            return [:]
        }

        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            logUsageResponseDiagnostics(http: http, data: data, reason: "jsonParseFailed:\(error.localizedDescription)")
            throw error
        }

        guard let object = parsed as? [String: Any] else {
            logUsageResponseDiagnostics(http: http, data: data, reason: "notDictionary:\(type(of: parsed))")
            throw QuotaFetchError.invalidResponse
        }
        return object
    }

    private func logUsageResponseDiagnostics(http: HTTPURLResponse, data: Data, reason: String) {
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "<none>"
        let bodyPreview: String = {
            let limit = 512
            if let text = String(data: data.prefix(limit), encoding: .utf8) {
                return text
            }
            return data.prefix(limit).map { String(format: "%02x", $0) }.joined()
        }()
        logger.error("usage response unparsable reason=\(reason) status=\(http.statusCode) contentType=\(contentType) bodyBytes=\(data.count) bodyPreview=\(bodyPreview)")
    }

    private func usageInfo(from object: [String: Any], plan: ClaudeSubscriptionPlan) -> AccountQuotaInfo {
        let fiveHour = quotaWindow(from: object["five_hour"])
        let sevenDay = quotaWindow(from: object["seven_day"])
        let monetary = monetaryQuota(from: object["extra_usage"])

        switch plan {
        case .pro, .max:
            if fiveHour != nil || sevenDay != nil {
                return .personal(plan: plan, fiveHour: fiveHour, sevenDay: sevenDay)
            }
            if let monetary {
                return .monetary(plan: plan, quota: monetary)
            }
        case .team, .enterprise:
            if let monetary {
                return .monetary(plan: plan, quota: monetary)
            }
            if fiveHour != nil || sevenDay != nil {
                return .personal(plan: plan, fiveHour: fiveHour, sevenDay: sevenDay)
            }
        case .unknown:
            if let monetary, fiveHour == nil, sevenDay == nil {
                return .monetary(plan: plan, quota: monetary)
            }
            if fiveHour != nil || sevenDay != nil {
                return .personal(plan: plan, fiveHour: fiveHour, sevenDay: sevenDay)
            }
        }

        return .unavailable(L10n.string(.quotaNoData))
    }

    private func quotaWindow(from value: Any?) -> QuotaWindow? {
        guard let object = value as? [String: Any] else {
            return nil
        }
        guard let rawUtilization = numberValue(object["used_percentage"])
            ?? numberValue(object["utilization"]) else {
            return nil
        }

        let usedPercentage = rawUtilization <= 1 ? rawUtilization * 100 : rawUtilization
        let resetsAt = dateValue(object["resets_at"])
            ?? dateValue(object["reset_at"])
            ?? dateValue(object["resetsAt"])
        return QuotaWindow(usedPercentage: usedPercentage, resetsAt: resetsAt)
    }

    private func monetaryQuota(from value: Any?) -> MonetaryQuota? {
        guard let object = value as? [String: Any] else {
            return nil
        }

        let used = numberValue(object["used_credits"])
            ?? numberValue(object["used_minor_units"])
            ?? numberValue(object["used"])
        let limit = numberValue(object["monthly_limit"])
            ?? numberValue(object["monthly_credit_limit"])
            ?? numberValue(object["limit"])
        var usedPercentage = numberValue(object["utilization"])
            ?? numberValue(object["used_percentage"])

        if let percentage = usedPercentage, percentage <= 1 {
            usedPercentage = percentage * 100
        } else if usedPercentage == nil, let used, let limit, limit > 0 {
            usedPercentage = used / limit * 100
        }

        let isEnabled = boolValue(object["is_enabled"]) ?? true
        guard isEnabled || used != nil || limit != nil || usedPercentage != nil else {
            return nil
        }

        let currency = stringValue(object["currency"]) ?? "USD"
        let resetsAt = dateValue(object["resets_at"])
            ?? dateValue(object["reset_at"])
            ?? dateValue(object["resetsAt"])
            ?? dateValue(object["current_period_end"])
            ?? nextMonthlyReset()

        return MonetaryQuota(
            usedMinorUnits: used,
            limitMinorUnits: limit,
            usedPercentage: usedPercentage,
            currency: currency,
            resetsAt: resetsAt
        )
    }

    private func errorMessage(from data: Data) -> String? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let error = object["error"] as? [String: Any],
           let message = stringValue(error["message"]) {
            return message
        }

        for key in ["message", "detail"] {
            if let message = stringValue(object[key]) {
                return message
            }
        }

        return nil
    }

    private func formURLEncoded(_ values: [String: String]) -> String {
        values
            .map { key, value in
                "\(urlFormEscape(key))=\(urlFormEscape(value))"
            }
            .joined(separator: "&")
    }

    private func urlFormEscape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func nextMonthlyReset() -> Date? {
        let calendar = Calendar.current
        let now = Date()
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) else {
            return nil
        }
        return calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth))
    }

    private func retryAfterDate(from http: HTTPURLResponse) -> Date? {
        guard let raw = http.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(raw) {
            return Date().addingTimeInterval(max(0, seconds))
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: raw)
    }

    private func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        return nil
    }

    private func numberValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? String {
            return Double(value)
        }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        if let value = value as? String {
            switch value.lowercased() {
            case "true", "1":
                return true
            case "false", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private func scopesValue(_ value: Any?) -> [String]? {
        if let values = value as? [String] {
            return values
        }
        if let value = value as? String {
            return value.split(separator: " ").map(String.init)
        }
        return nil
    }

    private func dateValue(_ value: Any?) -> Date? {
        if let number = numberValue(value) {
            if number > 10_000_000_000 {
                return Date(timeIntervalSince1970: number / 1000)
            }
            return Date(timeIntervalSince1970: number)
        }

        guard let string = stringValue(value), !string.isEmpty else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

private struct ParsedClaudeCredentials {
    var root: [String: Any]
    var oauthKey: String?
    var oauthObject: [String: Any]
    var oauth: ClaudeOAuthCredentials
}

private struct ClaudeOAuthCredentials {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Double?
    var scopes: [String]
    var subscriptionType: String?
    var rateLimitTier: String?
    var clientID: String?

    init(object: [String: Any]) throws {
        guard let accessToken = Self.stringValue(object["accessToken"])
            ?? Self.stringValue(object["access_token"]),
              !accessToken.isEmpty else {
            throw QuotaFetchError.missingOAuth
        }

        self.accessToken = accessToken
        refreshToken = Self.stringValue(object["refreshToken"])
            ?? Self.stringValue(object["refresh_token"])
        expiresAt = Self.numberValue(object["expiresAt"])
            ?? Self.numberValue(object["expires_at"])
            ?? Self.numberValue(object["expiry_date"])
        scopes = Self.scopesValue(object["scopes"])
            ?? Self.scopesValue(object["scope"])
            ?? []
        subscriptionType = Self.stringValue(object["subscriptionType"])
            ?? Self.stringValue(object["subscription_type"])
        rateLimitTier = Self.stringValue(object["rateLimitTier"])
            ?? Self.stringValue(object["rate_limit_tier"])
        clientID = Self.stringValue(object["clientId"])
            ?? Self.stringValue(object["client_id"])
    }

    var plan: ClaudeSubscriptionPlan {
        ClaudeSubscriptionPlan(rawValue: subscriptionType)
    }

    var isExpiringSoon: Bool {
        guard let expiresAt else {
            return false
        }
        let expiryDate: Date
        if expiresAt > 10_000_000_000 {
            expiryDate = Date(timeIntervalSince1970: expiresAt / 1000)
        } else {
            expiryDate = Date(timeIntervalSince1970: expiresAt)
        }
        return Date().addingTimeInterval(300) >= expiryDate
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private static func numberValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? String {
            return Double(value)
        }
        return nil
    }

    private static func scopesValue(_ value: Any?) -> [String]? {
        if let values = value as? [String] {
            return values
        }
        if let value = value as? String {
            return value.split(separator: " ").map(String.init)
        }
        return nil
    }
}

enum QuotaFetchError: LocalizedError, DebugLogDescribing {
    case missingOAuth
    case missingRefreshToken
    case invalidCredentials
    case invalidResponse
    case unauthorized
    case rateLimited(retryAfter: Date, message: String?)
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .missingOAuth:
            return L10n.string(.quotaUnavailable)
        case .missingRefreshToken:
            return L10n.string(.quotaUnavailable)
        case .invalidCredentials:
            return L10n.string(.quotaUnavailable)
        case .invalidResponse:
            return L10n.string(.quotaUnavailable)
        case .unauthorized:
            return L10n.string(.quotaUnavailable)
        case .rateLimited(_, let message):
            return message ?? L10n.string(.quotaUnavailable)
        case .httpStatus(_, let message):
            return message ?? L10n.string(.quotaUnavailable)
        }
    }

    var debugLogDescription: String {
        switch self {
        case .missingOAuth:
            return "OAuth credentials are missing or do not contain an access token."
        case .missingRefreshToken:
            return "OAuth refresh token is missing."
        case .invalidCredentials:
            return "Stored credentials JSON is invalid."
        case .invalidResponse:
            return "Quota service returned an invalid response."
        case .unauthorized:
            return "Quota service rejected the access token with HTTP 401."
        case .rateLimited(let retryAfter, let message):
            let seconds = Int(retryAfter.timeIntervalSinceNow.rounded())
            let base = "Quota service rate limited; retry in \(seconds)s"
            if let message {
                return "\(base) (\(message))"
            }
            return base
        case .httpStatus(let statusCode, let message):
            if let message {
                return "Quota service returned HTTP \(statusCode): \(message)"
            }
            return "Quota service returned HTTP \(statusCode) without an error message."
        }
    }
}
