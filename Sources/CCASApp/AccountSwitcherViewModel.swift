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
    @Published private(set) var isFetchingQuota = false
    @Published private(set) var lastQuotaUpdatedAt: Date?
    @Published private var statusMessage: StatusMessage = .none
    @Published var isBusy = false

    private let store: ClaudeAccountStore
    private let logger = DebugLogger(category: "ViewModel")
    private var quotaTask: Task<Void, Never>?
    private var quotaRefreshGeneration = 0
    private var lastQuotaSuccessAt: [Int: Date] = [:]
    private var quotaRateLimitedUntil: [Int: Date] = [:]
    private static let quotaRefreshCooldown: TimeInterval = 60

    init(store: ClaudeAccountStore = ClaudeAccountStore()) {
        self.store = store
        loadCachedQuotaInformation()
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

    func quotaAgeText(now: Date = Date()) -> String? {
        guard let lastQuotaUpdatedAt else {
            return nil
        }

        let seconds = max(0, Int(now.timeIntervalSince(lastQuotaUpdatedAt)))
        if seconds < 60 {
            return "\(seconds) s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) m"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) h"
        }

        return "\(hours / 24) d"
    }

    private func loadQuotaInformation() {
        quotaTask?.cancel()
        quotaRefreshGeneration += 1
        let generation = quotaRefreshGeneration

        let accounts = accounts
        guard !accounts.isEmpty else {
            quotaStates = [:]
            isFetchingQuota = false
            lastQuotaUpdatedAt = nil
            return
        }

        prepareQuotaStatesForRefresh(accounts: accounts)
        isFetchingQuota = true
        logger.notice("usage refresh start accountCount=\(accounts.count)")

        quotaTask = Task {
            var didUpdate = false

            for account in accounts {
                guard !Task.isCancelled else {
                    return
                }

                if let blockedUntil = self.quotaRateLimitedUntil[account.number],
                   blockedUntil > Date() {
                    let remaining = Int(blockedUntil.timeIntervalSinceNow.rounded())
                    self.logger.notice("usage refresh account skipped reason=rateLimited number=\(account.number) retryInSeconds=\(remaining)")
                    continue
                }

                if let lastSuccess = self.lastQuotaSuccessAt[account.number],
                   self.hasLoadedQuotaState(for: account.number) {
                    let age = Date().timeIntervalSince(lastSuccess)
                    if age < Self.quotaRefreshCooldown {
                        self.logger.notice("usage refresh account skipped reason=recentlySucceeded number=\(account.number) ageSeconds=\(Int(age))")
                        continue
                    }
                }

                do {
                    let info = try await self.store.usageInfo(for: account)
                    guard !Task.isCancelled else {
                        return
                    }
                    self.setQuotaState(.loaded(info), for: account.number)
                    self.lastQuotaSuccessAt[account.number] = Date()
                    self.quotaRateLimitedUntil[account.number] = nil
                    didUpdate = true
                    self.logger.notice("usage refresh account done number=\(account.number)")
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }
                    if case QuotaFetchError.rateLimited(let retryAfter, _) = error {
                        self.quotaRateLimitedUntil[account.number] = retryAfter
                    }
                    if !self.hasLoadedQuotaState(for: account.number) {
                        self.setQuotaState(.failed(error.localizedDescription), for: account.number)
                    }
                    self.logger.error("usage refresh account failed number=\(account.number) errorType=\(String(describing: type(of: error))) reason=\(Self.debugLogDescription(for: error))")
                }
            }

            guard generation == self.quotaRefreshGeneration else {
                return
            }

            if didUpdate {
                self.recordQuotaCacheUpdate(for: accounts)
            }
            self.isFetchingQuota = false
            self.logger.notice("usage refresh done")
        }
    }

    private func loadCachedQuotaInformation() {
        guard let snapshot = store.cachedQuotaSnapshot() else {
            return
        }

        var cachedStates: [Int: AccountQuotaLoadState] = [:]
        for (numberText, info) in snapshot.entries {
            guard let number = Int(numberText) else {
                continue
            }
            cachedStates[number] = .loaded(info)
            lastQuotaSuccessAt[number] = snapshot.updatedAt
        }

        quotaStates = cachedStates
        lastQuotaUpdatedAt = cachedStates.isEmpty ? nil : snapshot.updatedAt
        logger.notice("usage cache loaded stateCount=\(cachedStates.count)")
    }

    private func prepareQuotaStatesForRefresh(accounts: [ManagedAccount]) {
        let accountNumbers = Set(accounts.map(\.number))
        var states = quotaStates.filter { accountNumbers.contains($0.key) }

        for account in accounts where !Self.isLoadedQuotaState(states[account.number]) {
            states[account.number] = .loading
        }

        quotaStates = states

        if !states.contains(where: { accountNumbers.contains($0.key) && Self.isLoadedQuotaState($0.value) }) {
            lastQuotaUpdatedAt = nil
        }
    }

    private func setQuotaState(_ state: AccountQuotaLoadState, for number: Int) {
        var states = quotaStates
        states[number] = state
        quotaStates = states
    }

    private func hasLoadedQuotaState(for number: Int) -> Bool {
        Self.isLoadedQuotaState(quotaStates[number])
    }

    private static func isLoadedQuotaState(_ state: AccountQuotaLoadState?) -> Bool {
        guard let state else {
            return false
        }

        if case .loaded = state {
            return true
        }
        return false
    }

    private static func debugLogDescription(for error: Error) -> String {
        if let error = error as? DebugLogDescribing {
            return error.debugLogDescription
        }

        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? String(describing: error) : description
    }

    private func recordQuotaCacheUpdate(for accounts: [ManagedAccount]) {
        let accountNumbers = Set(accounts.map(\.number))
        var entries: [String: AccountQuotaInfo] = [:]

        for (number, state) in quotaStates where accountNumbers.contains(number) {
            guard case .loaded(let info) = state else {
                continue
            }
            entries[String(number)] = info
        }

        guard !entries.isEmpty else {
            return
        }

        let updatedAt = Date()
        lastQuotaUpdatedAt = updatedAt
        store.writeQuotaSnapshot(AccountQuotaCacheSnapshot(updatedAt: updatedAt, entries: entries))
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
