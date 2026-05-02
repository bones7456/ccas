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
    @Published private var statusMessage: StatusMessage = .none
    @Published var isBusy = false

    private let store: ClaudeAccountStore

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
        }
    }

    func addCurrentAccount() {
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
        }
    }

    func switchTo(_ account: ManagedAccount) {
        guard !account.isActive else {
            statusMessage = .alreadyCurrent
            return
        }

        run {
            try self.store.switchToAccount(number: account.number)
            self.currentIdentity = try self.store.currentIdentity()
            self.accounts = try self.store.listAccounts()
            self.statusMessage = .switched(account.number)
        }
    }

    private func run(_ action: @escaping () throws -> Void) {
        isBusy = true
        Task {
            do {
                try action()
            } catch {
                statusMessage = .error(error.localizedDescription)
            }
            isBusy = false
        }
    }
}
