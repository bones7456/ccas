import Foundation
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
    @Published private(set) var quotaStates: [Int: AccountQuotaLoadState] = [:]
    @Published private var statusMessage: StatusMessage = .none
    @Published var isBusy = false

    private let store: ClaudeAccountStore
    private let logger = DebugLogger(category: "ViewModel")
    private var quotaTask: Task<Void, Never>?

    init(store: ClaudeAccountStore = ClaudeAccountStore()) {
        self.store = store
    }

    deinit {
        quotaTask?.cancel()
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
            self.logger.notice("refresh completed accountCount=\(self.accounts.count) hasCurrentIdentity=\((self.currentIdentity != nil))")
        } onSuccess: {
            self.loadQuotaInformation()
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
            self.logger.notice("add account completed accountCount=\(self.accounts.count) hasCurrentIdentity=\((self.currentIdentity != nil))")
        } onSuccess: {
            self.loadQuotaInformation()
        }
    }

    func switchTo(_ account: ManagedAccount) {
        logger.notice("switch requested number=\(account.number) isActive=\(account.isActive)")
        guard !account.isActive else {
            statusMessage = .alreadyCurrent
            logger.notice("switch skipped alreadyActive number=\(account.number)")
            return
        }

        run {
            try self.store.switchToAccount(number: account.number)
            self.currentIdentity = try self.store.currentIdentity()
            self.accounts = try self.store.listAccounts()
            self.statusMessage = .switched(account.number)
            self.logger.notice("switch completed number=\(account.number) hasCurrentIdentity=\((self.currentIdentity != nil))")
        } onSuccess: {
            self.loadQuotaInformation()
        }
    }

    func quotaState(for account: ManagedAccount) -> AccountQuotaLoadState? {
        quotaStates[account.number]
    }

    private func loadQuotaInformation() {
        quotaTask?.cancel()

        let accounts = accounts
        guard !accounts.isEmpty else {
            quotaStates = [:]
            return
        }

        quotaStates = Dictionary(uniqueKeysWithValues: accounts.map { ($0.number, .loading) })
        logger.notice("usage refresh start accountCount=\(accounts.count)")

        quotaTask = Task {
            for account in accounts {
                guard !Task.isCancelled else {
                    return
                }

                do {
                    let info = try await self.store.usageInfo(for: account)
                    guard !Task.isCancelled else {
                        return
                    }
                    self.setQuotaState(.loaded(info), for: account.number)
                    self.logger.notice("usage refresh account done number=\(account.number)")
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }
                    self.setQuotaState(.failed(error.localizedDescription), for: account.number)
                    self.logger.error("usage refresh account failed number=\(account.number) errorType=\(String(describing: type(of: error)))")
                }
            }
            self.logger.notice("usage refresh done")
        }
    }

    private func setQuotaState(_ state: AccountQuotaLoadState, for number: Int) {
        var states = quotaStates
        states[number] = state
        quotaStates = states
    }

    private func run(_ action: @escaping () throws -> Void, onSuccess: (() -> Void)? = nil) {
        logger.notice("operation start")
        isBusy = true
        Task {
            do {
                try action()
                onSuccess?()
            } catch {
                self.logger.error("operation failed errorType=\(String(describing: type(of: error)))")
                statusMessage = .error(error.localizedDescription)
            }
            self.logger.notice("operation end")
            isBusy = false
        }
    }
}
