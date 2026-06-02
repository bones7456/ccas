import AppKit
import Foundation
import SwiftUI

enum StatusMessage: Equatable {
    case none
    case noAccounts
    case alreadyCurrent
    case added(Int)
    case updatedExisting(Int)
    case switched(Int)
    case removed(Int)
    case purged
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
        case .removed(let number):
            return L10n.string(.statusRemovedAccount, number)
        case .purged:
            return L10n.string(.statusPurged)
        case .error(let text):
            return text
        }
    }
}

enum QuotaSeverity {
    case normal, warning, critical

    init(percent: Double) {
        switch percent {
        case ..<70: self = .normal
        case ..<85: self = .warning
        default: self = .critical
        }
    }

    var color: Color {
        switch self {
        case .normal: return Color(red: 0.30, green: 0.72, blue: 0.45)
        case .warning: return Color(red: 0.95, green: 0.62, blue: 0.20)
        case .critical: return Color(red: 0.86, green: 0.36, blue: 0.36)
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
    @Published private(set) var appearanceTick = false

    private let store: ClaudeAccountStore
    nonisolated(unsafe) private var appearanceObserver: NSObjectProtocol?
    private let logger = DebugLogger(category: "ViewModel")
    private var quotaTask: Task<Void, Never>?
    private var quotaRefreshGeneration = 0
    private var lastQuotaSuccessAt: [Int: Date] = [:]
    private var quotaRateLimitedUntil: [Int: Date] = [:]
    private var backgroundRefreshTimer: Timer?
    private static let quotaRefreshCooldown: TimeInterval = 60
    private static let backgroundRefreshInterval: TimeInterval = 300

    init(store: ClaudeAccountStore = ClaudeAccountStore()) {
        self.store = store
        loadCachedQuotaInformation()
        registerWorkspaceObservers()
        registerAppearanceObserver()
        startBackgroundRefresh()
    }

    deinit {
        quotaTask?.cancel()
        if let appearanceObserver { DistributedNotificationCenter.default().removeObserver(appearanceObserver) }
    }

    var activeAccount: ManagedAccount? {
        accounts.first(where: \.isActive)
    }

    var activeQuotaPercent: Double? {
        guard let activeAccount,
              case .loaded(let info) = quotaStates[activeAccount.number] else {
            return nil
        }
        return Self.menuBarPercent(in: info)
    }

    var activeQuotaSeverity: QuotaSeverity? {
        activeQuotaPercent.map(QuotaSeverity.init(percent:))
    }

    private static func menuBarPercent(in info: AccountQuotaInfo) -> Double? {
        switch info {
        case .personal(_, let fiveHour, _):
            return fiveHour?.usedPercentage
        case .monetary(_, let quota):
            return quota.usedPercentage
        case .unavailable:
            return nil
        }
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
        } onSuccess: {
            self.loadQuotaInformation()
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
        } onSuccess: {
            self.loadQuotaInformation()
        }
    }

    func removeAccount(_ account: ManagedAccount) {
        let number = account.number
        run {
            try self.store.removeAccount(number: number)
            self.currentIdentity = try self.store.currentIdentity()
            self.accounts = try self.store.listAccounts()
            self.quotaStates.removeValue(forKey: number)
            self.lastQuotaSuccessAt.removeValue(forKey: number)
            self.quotaRateLimitedUntil.removeValue(forKey: number)
            self.statusMessage = .removed(number)
            if self.accounts.isEmpty {
                self.lastQuotaUpdatedAt = nil
            } else {
                self.recordQuotaCacheUpdate(for: self.accounts)
            }
        }
    }

    func purgeAllData() {
        quotaTask?.cancel()
        run {
            try self.store.purgeAllData()
            self.currentIdentity = try self.store.currentIdentity()
            self.accounts = []
            self.quotaStates = [:]
            self.lastQuotaSuccessAt = [:]
            self.quotaRateLimitedUntil = [:]
            self.lastQuotaUpdatedAt = nil
            self.isFetchingQuota = false
            self.statusMessage = .purged
        }
    }

    func switchTo(_ account: ManagedAccount) {
        guard !account.isActive else {
            statusMessage = .alreadyCurrent
            return
        }

        runAsync {
            try await self.store.switchToAccount(number: account.number)
            self.currentIdentity = try self.store.currentIdentity()
            self.accounts = try self.store.listAccounts()
            self.statusMessage = .switched(account.number)
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

        quotaTask = Task {
            var didUpdate = false

            for account in accounts {
                guard !Task.isCancelled else {
                    return
                }

                if let blockedUntil = self.quotaRateLimitedUntil[account.number],
                   blockedUntil > Date() {
                    continue
                }

                if let lastSuccess = self.lastQuotaSuccessAt[account.number],
                   self.hasLoadedQuotaState(for: account.number) {
                    let age = Date().timeIntervalSince(lastSuccess)
                    if age < Self.quotaRefreshCooldown {
                        continue
                    }
                }

                do {
                    let info = try await self.store.usageInfo(for: account)
                    guard !Task.isCancelled else {
                        return
                    }
                    self.setQuotaState(.loaded(info), for: account.number)
                    self.quotaRateLimitedUntil[account.number] = nil
                    if case .unavailable = info {
                        // Not a real success: usage couldn't be resolved (typically
                        // the active account's live token is expired and only Claude
                        // Code may refresh it — see ClaudeAccountStore.usageInfo).
                        // Don't arm the 60s cooldown, so the next refresh retries
                        // this account immediately once the token recovers.
                        self.lastQuotaSuccessAt.removeValue(forKey: account.number)
                    } else {
                        self.lastQuotaSuccessAt[account.number] = Date()
                        didUpdate = true
                    }
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
            // Never persist an unavailable result — a stale "Usage unavailable"
            // should not survive across launches once the token recovers.
            if case .unavailable = info {
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

    private func startBackgroundRefresh() {
        backgroundRefreshTimer?.invalidate()
        let timer = Timer(timeInterval: Self.backgroundRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadQuotaInformation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        backgroundRefreshTimer = timer
    }

    private func registerWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.backgroundRefreshTimer?.invalidate()
                self?.backgroundRefreshTimer = nil
            }
        }
        nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.startBackgroundRefresh()
                self?.loadQuotaInformation()
            }
        }
    }

    private func registerAppearanceObserver() {
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appearanceTick.toggle()
            }
        }
    }

    private func run(_ action: @escaping () throws -> Void, onSuccess: (() -> Void)? = nil) {
        isBusy = true
        Task {
            do {
                try action()
                onSuccess?()
            } catch {
                self.logger.error("operation failed errorType=\(String(describing: type(of: error)))")
                statusMessage = .error(error.localizedDescription)
            }
            isBusy = false
        }
    }

    private func runAsync(_ action: @escaping () async throws -> Void, onSuccess: (() -> Void)? = nil) {
        isBusy = true
        Task {
            do {
                try await action()
                onSuccess?()
            } catch {
                self.logger.error("operation failed errorType=\(String(describing: type(of: error)))")
                statusMessage = .error(error.localizedDescription)
            }
            isBusy = false
        }
    }
}
