import Foundation

enum L10n {
    enum Key {
        case accountDisplay
        case addAccount
        case alreadyCurrent
        case cancel
        case checkForUpdates
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
        case errorInvalidSavedCredentials
        case errorKeychain
        case errorMissingBackupData
        case errorMissingCredentials
        case errorMissingLiveCredentials
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
        case purgeAll
        case purgeConfirm
        case purgeConfirmBody
        case purgeConfirmTitle
        case quotaFailed
        case quotaFiveHour
        case quotaLoading
        case quotaNoData
        case quotaReset
        case quotaSpent
        case quotaUnavailable
        case quotaUnknownPlan
        case quotaWeek
        case quotaUnlimited
        case quit
        case redactSensitive
        case refresh
        case removeAccount
        case removeAccountActiveWarning
        case removeAccountConfirm
        case removeAccountConfirmBody
        case removeAccountConfirmTitle
        case revealInFinder
        case signedOut
        case statusAddedAccount
        case statusPurged
        case statusRemovedAccount
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
        .cancel: "Cancel",
        .checkForUpdates: "Check for Updates…",
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
        .errorInvalidSavedCredentials: "Saved credentials for Account %d are no longer valid. Sign in to that account in Claude Code, then choose Add Account to update it.",
        .errorKeychain: "Keychain operation failed: %@",
        .errorMissingBackupData: "Backup data is incomplete for account %d.",
        .errorMissingCredentials: "Account %d is missing saved credentials. Sign in as %@ in Claude Code, then choose Add Account to update it.",
        .errorMissingLiveCredentials: "Sign in to Account %d in Claude Code, then try again.",
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
        .purgeAll: "Reset all data…",
        .purgeConfirm: "Reset",
        .purgeConfirmBody: "This permanently deletes ~/.ccas and every backup credential CCAS stored in Keychain. Your current Claude Code login is left untouched, but you will lose the ability to switch back to other accounts unless you re-add them.",
        .purgeConfirmTitle: "Reset all CCAS data?",
        .quotaFailed: "Usage unavailable: %@",
        .quotaFiveHour: "5h",
        .quotaLoading: "Loading usage...",
        .quotaNoData: "No usage data yet",
        .quotaReset: "Resets %@",
        .quotaSpent: "%@ / %@ spent",
        .quotaUnavailable: "Usage unavailable",
        .quotaUnknownPlan: "Unknown",
        .quotaWeek: "Week",
        .quotaUnlimited: "Unlimited",
        .quit: "Quit",
        .redactSensitive: "Hide Sensitive Info",
        .refresh: "Refresh",
        .removeAccount: "Remove",
        .removeAccountActiveWarning: "This is the account currently signed in to Claude Code. Your live login stays, but the backup will be gone and you cannot switch back to it unless you add it again.",
        .removeAccountConfirm: "Remove",
        .removeAccountConfirmBody: "Account %d (%@) will be deleted from CCAS, along with its Keychain backup and config snapshot.",
        .removeAccountConfirmTitle: "Remove this account?",
        .revealInFinder: "Show in Finder",
        .signedOut: "Signed out",
        .statusAddedAccount: "Added account %d",
        .statusPurged: "All CCAS data has been removed.",
        .statusRemovedAccount: "Removed account %d",
        .statusSwitchedAccount: "Switched to account %d. Restart Claude Code to use it.",
        .statusUpdatedExistingAccount: "Still detected account %d. Backup updated; no new account was added.",
        .switchToAccount: "Switch to this account"
    ]

    private static let chinese: [Key: String] = [
        .accountDisplay: "账号 %d · %@",
        .addAccount: "添加账号",
        .alreadyCurrent: "已经是当前账号",
        .cancel: "取消",
        .checkForUpdates: "检查更新…",
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
        .errorInvalidSavedCredentials: "账号 %d 的已保存凭据已失效。请先在 Claude Code 登录该账号，再点添加账号更新。",
        .errorKeychain: "Keychain 操作失败：%@",
        .errorMissingBackupData: "账号 %d 的备份数据不完整。",
        .errorMissingCredentials: "账号 %d 缺少已保存凭据。请先在 Claude Code 登录 %@，再点添加账号更新。",
        .errorMissingLiveCredentials: "请先在 Claude Code 登录账号 %d，然后重试。",
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
        .purgeAll: "清除所有数据…",
        .purgeConfirm: "清除",
        .purgeConfirmBody: "将永久删除 ~/.ccas 目录，以及 CCAS 在 Keychain 中保存的所有备份凭据。Claude Code 当前登录状态不受影响，但除非重新添加，否则将无法切换回其他账号。",
        .purgeConfirmTitle: "清除所有 CCAS 数据？",
        .quotaFailed: "额度不可用：%@",
        .quotaFiveHour: "5小时",
        .quotaLoading: "正在获取额度...",
        .quotaNoData: "暂无额度数据",
        .quotaReset: "%@ 重置",
        .quotaSpent: "已用 %@ / %@",
        .quotaUnavailable: "额度不可用",
        .quotaUnknownPlan: "未知",
        .quotaWeek: "本周",
        .quotaUnlimited: "无限额",
        .quit: "退出",
        .redactSensitive: "隐藏敏感信息",
        .refresh: "刷新",
        .removeAccount: "删除",
        .removeAccountActiveWarning: "这是当前 Claude Code 登录的账号。删除后当前登录态保留，但备份会被清除，除非重新添加，否则无法切换回这个账号。",
        .removeAccountConfirm: "删除",
        .removeAccountConfirmBody: "账号 %d（%@）以及它在 Keychain 的备份和配置快照都会被删除。",
        .removeAccountConfirmTitle: "确认删除该账号？",
        .revealInFinder: "在 Finder 中显示",
        .signedOut: "未登录",
        .statusAddedAccount: "已添加账号 %d",
        .statusPurged: "已清除所有 CCAS 数据",
        .statusRemovedAccount: "已删除账号 %d",
        .statusSwitchedAccount: "已切换到账号 %d，请重启 Claude Code",
        .statusUpdatedExistingAccount: "检测到的仍是账号 %d，已更新备份；没有新增账号",
        .switchToAccount: "切换到该账号"
    ]
}
