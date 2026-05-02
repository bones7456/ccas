import Foundation

enum L10n {
    enum Key {
        case accountDisplay
        case addAccount
        case alreadyCurrent
        case claudeCode
        case currentAccount
        case errorAccountNotFound
        case errorAccountNotManaged
        case errorAcquireLock
        case errorClaudeConfigNotFound
        case errorCreateLock
        case errorCredentialEncoding
        case errorFileSystem
        case errorInvalidBackupConfig
        case errorInvalidClaudeConfig
        case errorKeychain
        case errorMissingBackupData
        case errorMissingCredentials
        case errorNoActiveClaudeAccount
        case errorNoClaudeCredentials
        case errorNoManagedAccounts
        case errorReadSequence
        case errorUnreadableCredentials
        case noAccountsBody
        case noAccountsStatus
        case noAccountsTitle
        case notAdded
        case personal
        case quit
        case refresh
        case signedOut
        case statusAddedAccount
        case statusSwitchedAccount
        case statusUpdatedExistingAccount
        case switchToAccount
    }

    private enum Language {
        case english
        case chinese
    }

    static func string(_ key: Key, _ arguments: CVarArg...) -> String {
        let format = table(for: language)[key] ?? english[key] ?? ""
        return String(format: format, locale: locale, arguments: arguments)
    }

    private static var language: Language {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("zh") ? .chinese : .english
    }

    private static var locale: Locale {
        switch language {
        case .english:
            return Locale(identifier: "en")
        case .chinese:
            return Locale(identifier: "zh-Hans")
        }
    }

    private static func table(for language: Language) -> [Key: String] {
        switch language {
        case .english:
            return english
        case .chinese:
            return chinese
        }
    }

    private static let english: [Key: String] = [
        .accountDisplay: "Account %d · %@",
        .addAccount: "Add Account",
        .alreadyCurrent: "This account is already active",
        .claudeCode: "Claude Code",
        .currentAccount: "Current account",
        .errorAccountNotFound: "Account %d was not found.",
        .errorAccountNotManaged: "Current account %@ has not been added.",
        .errorAcquireLock: "Could not acquire lock: %@",
        .errorClaudeConfigNotFound: "Claude Code config file was not found.",
        .errorCreateLock: "Could not create lock file: %@",
        .errorCredentialEncoding: "Could not encode credentials.",
        .errorFileSystem: "File operation failed: %@",
        .errorInvalidBackupConfig: "Backup config is invalid for account %d.",
        .errorInvalidClaudeConfig: "Claude Code config is not valid JSON: %@",
        .errorKeychain: "Keychain operation failed: %@",
        .errorMissingBackupData: "Backup data is incomplete for account %d.",
        .errorMissingCredentials: "Account %d is missing saved credentials. Sign in as %@ in Claude Code, then choose Add Account to update it.",
        .errorNoActiveClaudeAccount: "No active Claude Code account was found. Please sign in with Claude Code first.",
        .errorNoClaudeCredentials: "No Claude Code credentials were found. Please finish signing in with Claude Code first.",
        .errorNoManagedAccounts: "No accounts have been added yet.",
        .errorReadSequence: "Could not read sequence.json: %@",
        .errorUnreadableCredentials: "Could not read Claude Code credentials.",
        .noAccountsBody: "Sign in with Claude Code, then add the account here.",
        .noAccountsStatus: "No accounts added yet",
        .noAccountsTitle: "No Accounts",
        .notAdded: "Not added",
        .personal: "personal",
        .quit: "Quit",
        .refresh: "Refresh",
        .signedOut: "Signed out",
        .statusAddedAccount: "Added account %d",
        .statusSwitchedAccount: "Switched to account %d. Restart Claude Code to use it.",
        .statusUpdatedExistingAccount: "Still detected account %d. Backup updated; no new account was added.",
        .switchToAccount: "Switch to this account"
    ]

    private static let chinese: [Key: String] = [
        .accountDisplay: "账号 %d · %@",
        .addAccount: "添加账号",
        .alreadyCurrent: "已经是当前账号",
        .claudeCode: "Claude Code",
        .currentAccount: "当前账号",
        .errorAccountNotFound: "没有找到账号 %d。",
        .errorAccountNotManaged: "当前账号 %@ 还没有添加到列表。",
        .errorAcquireLock: "无法获得锁：%@",
        .errorClaudeConfigNotFound: "没有找到 Claude Code 配置文件。",
        .errorCreateLock: "无法创建锁文件：%@",
        .errorCredentialEncoding: "无法编码凭据。",
        .errorFileSystem: "文件操作失败：%@",
        .errorInvalidBackupConfig: "账号 %d 的备份配置无效。",
        .errorInvalidClaudeConfig: "Claude Code 配置文件不是有效 JSON：%@",
        .errorKeychain: "Keychain 操作失败：%@",
        .errorMissingBackupData: "账号 %d 的备份数据不完整。",
        .errorMissingCredentials: "账号 %d 缺少已保存凭据。请先在 Claude Code 登录 %@，再点添加账号更新。",
        .errorNoActiveClaudeAccount: "没有找到当前 Claude Code 登录账号。请先在 Claude Code 登录。",
        .errorNoClaudeCredentials: "没有找到 Claude Code 凭据。请先完成 Claude Code 登录。",
        .errorNoManagedAccounts: "还没有添加任何账号。",
        .errorReadSequence: "无法读取 sequence.json：%@",
        .errorUnreadableCredentials: "读取 Claude Code 凭据失败。",
        .noAccountsBody: "先在 Claude Code 登录，然后点添加账号。",
        .noAccountsStatus: "还没有添加账号",
        .noAccountsTitle: "暂无账号",
        .notAdded: "未添加",
        .personal: "个人",
        .quit: "退出",
        .refresh: "刷新",
        .signedOut: "未登录",
        .statusAddedAccount: "已添加账号 %d",
        .statusSwitchedAccount: "已切换到账号 %d，请重启 Claude Code",
        .statusUpdatedExistingAccount: "检测到的仍是账号 %d，已更新备份；没有新增账号",
        .switchToAccount: "切换到该账号"
    ]
}
