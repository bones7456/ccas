import Foundation
import OSLog
import SwiftUI

enum StatusMessage: Equatable {
    case none
    case noAccounts
    case alreadyCurrent
    case added(Int)
    case updatedExisting(Int)
    case switched(Int)
    case error(String)

    var text: String {
        switch self {
        case .none:
            return ""
        case .noAccounts:
            return L10n.string(.noAccountsStatus)
        case .alreadyCurrent:
            return L10n.string(.alreadyCurrent)
        case .added(let number):
            return L10n.string(.statusAddedAccount, number)
        case .updatedExisting(let number):
            return L10n.string(.statusUpdatedExistingAccount, number)
        case .switched(let number):
            return L10n.string(.statusSwitchedAccount, number)
        case .error(let text):
            return text
        }
    }
}

@MainActor
final class AccountSwitcherViewModel: ObservableObject {
    @Published private(set) var accounts: [ManagedAccount] = []
    @Published private(set) var currentIdentity: AccountIdentity?
    @Published private var statusMessage: StatusMessage = .none
    @Published var isBusy = false

    private let store: ClaudeAccountStore
    private let logger = Logger(subsystem: "li.luy.ccas", category: "ViewModel")

    init(store: ClaudeAccountStore = ClaudeAccountStore()) {
        self.store = store
    }

    var currentTitle: String {
        if let active = accounts.first(where: \.isActive) {
            return active.record.email
        }

        if let currentIdentity {
            return currentIdentity.email
        }

        return L10n.string(.signedOut)
    }

    var currentSubtitle: String {
        if let active = accounts.first(where: \.isActive) {
            return L10n.string(.accountDisplay, active.number, active.displayTag)
        }

        if currentIdentity != nil {
            return L10n.string(.notAdded)
        }

        return L10n.string(.claudeCode)
    }

    var statusText: String {
        statusMessage.text
    }

    func refresh() {
        logger.notice("refresh requested")
        run {
            self.currentIdentity = try self.store.currentIdentity()
            self.accounts = try self.store.listAccounts()
            if self.accounts.isEmpty {
                if self.statusMessage == .none {
                    self.statusMessage = .noAccounts
                }
            } else if self.statusMessage == .noAccounts {
                self.statusMessage = .none
            }
            self.logger.notice("refresh completed accountCount=\(self.accounts.count, privacy: .public) currentEmail=\((self.currentIdentity?.email ?? "<none>"), privacy: .public)")
        }
    }

    func addCurrentAccount() {
        logger.notice("add account requested")
        run {
            let result = try self.store.addCurrentAccount()
            self.currentIdentity = try self.store.currentIdentity()
            self.accounts = try self.store.listAccounts()

            switch result {
            case .added(let account):
                self.statusMessage = .added(account.number)
            case .updated(let account):
                self.statusMessage = .updatedExisting(account.number)
            }
            self.logger.notice("add account completed currentEmail=\((self.currentIdentity?.email ?? "<none>"), privacy: .public) accountCount=\(self.accounts.count, privacy: .public)")
        }
    }

    func switchTo(_ account: ManagedAccount) {
        logger.notice("switch requested number=\(account.number, privacy: .public) email=\(account.record.email, privacy: .public) isActive=\(account.isActive, privacy: .public)")
        guard !account.isActive else {
            statusMessage = .alreadyCurrent
            logger.notice("switch skipped alreadyActive number=\(account.number, privacy: .public)")
            return
        }

        run {
            try self.store.switchToAccount(number: account.number)
            self.currentIdentity = try self.store.currentIdentity()
            self.accounts = try self.store.listAccounts()
            self.statusMessage = .switched(account.number)
            self.logger.notice("switch completed number=\(account.number, privacy: .public) currentEmail=\((self.currentIdentity?.email ?? "<none>"), privacy: .public)")
        }
    }

    private func run(_ action: @escaping () throws -> Void) {
        logger.notice("operation start")
        isBusy = true
        Task {
            do {
                try action()
            } catch {
                self.logger.error("operation failed error=\(error.localizedDescription, privacy: .public)")
                statusMessage = .error(error.localizedDescription)
            }
            self.logger.notice("operation end")
            isBusy = false
        }
    }
}
