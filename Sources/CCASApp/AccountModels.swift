import Foundation

struct DebugLogger {
    #if DEBUG
    private let category: String

    init(category: String) {
        self.category = category
    }

    @inline(__always)
    func notice(_ message: @autoclosure () -> String) {
        NSLog("[CCAS][\(category)] \(message())")
    }

    @inline(__always)
    func error(_ message: @autoclosure () -> String) {
        NSLog("[CCAS][\(category)] ERROR \(message())")
    }
    #else
    init(category: String) {}

    @inline(__always)
    func notice(_ message: @autoclosure () -> String) {}

    @inline(__always)
    func error(_ message: @autoclosure () -> String) {}
    #endif
}

protocol DebugLogDescribing {
    var debugLogDescription: String { get }
}

struct AccountRecord: Codable, Equatable {
    var email: String
    var uuid: String
    var organizationUuid: String
    var organizationName: String
    var added: String
    var hasOrganizationFields: Bool = true

    enum CodingKeys: String, CodingKey {
        case email
        case uuid
        case organizationUuid
        case organizationName
        case added
    }

    init(
        email: String,
        uuid: String,
        organizationUuid: String,
        organizationName: String,
        added: String,
        hasOrganizationFields: Bool = true
    ) {
        self.email = email
        self.uuid = uuid
        self.organizationUuid = organizationUuid
        self.organizationName = organizationName
        self.added = added
        self.hasOrganizationFields = hasOrganizationFields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = try container.decode(String.self, forKey: .email)
        uuid = try container.decodeIfPresent(String.self, forKey: .uuid) ?? ""
        organizationUuid = try container.decodeIfPresent(String.self, forKey: .organizationUuid) ?? ""
        organizationName = try container.decodeIfPresent(String.self, forKey: .organizationName) ?? ""
        added = try container.decodeIfPresent(String.self, forKey: .added) ?? Timestamp.now()
        hasOrganizationFields = container.contains(.organizationUuid)
            || container.contains(.organizationName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(email, forKey: .email)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(organizationUuid, forKey: .organizationUuid)
        try container.encode(organizationName, forKey: .organizationName)
        try container.encode(added, forKey: .added)
    }
}

struct SequenceData: Codable, Equatable {
    var activeAccountNumber: Int?
    var lastUpdated: String
    var sequence: [Int]
    var accounts: [String: AccountRecord]

    static func empty(now: String = Timestamp.now()) -> SequenceData {
        SequenceData(
            activeAccountNumber: nil,
            lastUpdated: now,
            sequence: [],
            accounts: [:]
        )
    }
}

struct AccountIdentity: Equatable {
    var email: String
    var accountUuid: String
    var organizationUuid: String
    var organizationName: String
}

struct ManagedAccount: Identifiable, Equatable {
    var number: Int
    var record: AccountRecord
    var isActive: Bool

    var id: Int { number }

    var displayTag: String {
        record.organizationName.isEmpty ? L10n.string(.personal) : record.organizationName
    }
}

enum ClaudeSubscriptionPlan: String, Codable, Equatable {
    case pro
    case max
    case team
    case enterprise
    case unknown

    init(rawValue: String?) {
        switch rawValue?.lowercased() {
        case "pro":
            self = .pro
        case "max":
            self = .max
        case "team":
            self = .team
        case "enterprise":
            self = .enterprise
        default:
            self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .pro:
            return "Pro"
        case .max:
            return "Max"
        case .team:
            return "Team"
        case .enterprise:
            return "Enterprise"
        case .unknown:
            return L10n.string(.quotaUnknownPlan)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self.init(rawValue: Optional(value))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct QuotaWindow: Codable, Equatable {
    var usedPercentage: Double
    var resetsAt: Date?
}

struct MonetaryQuota: Codable, Equatable {
    var usedMinorUnits: Double?
    var limitMinorUnits: Double?
    var usedPercentage: Double?
    var currency: String
    var resetsAt: Date?
}

enum AccountQuotaInfo: Codable, Equatable {
    case personal(plan: ClaudeSubscriptionPlan, fiveHour: QuotaWindow?, sevenDay: QuotaWindow?)
    case monetary(plan: ClaudeSubscriptionPlan, quota: MonetaryQuota)
    case unavailable(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case plan
        case fiveHour
        case sevenDay
        case quota
        case message
    }

    private enum Kind: String, Codable {
        case personal
        case monetary
        case unavailable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .personal:
            self = .personal(
                plan: try container.decode(ClaudeSubscriptionPlan.self, forKey: .plan),
                fiveHour: try container.decodeIfPresent(QuotaWindow.self, forKey: .fiveHour),
                sevenDay: try container.decodeIfPresent(QuotaWindow.self, forKey: .sevenDay)
            )
        case .monetary:
            self = .monetary(
                plan: try container.decode(ClaudeSubscriptionPlan.self, forKey: .plan),
                quota: try container.decode(MonetaryQuota.self, forKey: .quota)
            )
        case .unavailable:
            self = .unavailable(try container.decode(String.self, forKey: .message))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .personal(let plan, let fiveHour, let sevenDay):
            try container.encode(Kind.personal, forKey: .kind)
            try container.encode(plan, forKey: .plan)
            try container.encodeIfPresent(fiveHour, forKey: .fiveHour)
            try container.encodeIfPresent(sevenDay, forKey: .sevenDay)
        case .monetary(let plan, let quota):
            try container.encode(Kind.monetary, forKey: .kind)
            try container.encode(plan, forKey: .plan)
            try container.encode(quota, forKey: .quota)
        case .unavailable(let message):
            try container.encode(Kind.unavailable, forKey: .kind)
            try container.encode(message, forKey: .message)
        }
    }
}

enum AccountQuotaLoadState: Equatable {
    case loading
    case loaded(AccountQuotaInfo)
    case failed(String)
}

struct AccountQuotaCacheSnapshot: Codable, Equatable {
    var updatedAt: Date
    var entries: [String: AccountQuotaInfo]
}

enum AddAccountResult: Equatable {
    case added(ManagedAccount)
    case updated(ManagedAccount)

    var account: ManagedAccount {
        switch self {
        case .added(let account), .updated(let account):
            return account
        }
    }
}

enum AccountSwitcherError: LocalizedError {
    case noActiveClaudeAccount
    case noClaudeCredentials
    case unreadableCredentials
    case claudeConfigNotFound
    case invalidClaudeConfig(URL)
    case noManagedAccounts
    case accountNotFound(Int)
    case accountNotManaged(String)
    case missingBackupData(Int)
    case missingCredentials(Int, String)
    case missingLiveCredentials(Int)
    case invalidBackupConfig(Int)
    case invalidSavedCredentials(Int)
    case keychain(String)
    case fileSystem(String)

    var errorDescription: String? {
        switch self {
        case .noActiveClaudeAccount:
            return L10n.string(.errorNoActiveClaudeAccount)
        case .noClaudeCredentials:
            return L10n.string(.errorNoClaudeCredentials)
        case .unreadableCredentials:
            return L10n.string(.errorUnreadableCredentials)
        case .claudeConfigNotFound:
            return L10n.string(.errorClaudeConfigNotFound)
        case .invalidClaudeConfig(let url):
            return L10n.string(.errorInvalidClaudeConfig, url.path)
        case .noManagedAccounts:
            return L10n.string(.errorNoManagedAccounts)
        case .accountNotFound(let number):
            return L10n.string(.errorAccountNotFound, number)
        case .accountNotManaged(let email):
            return L10n.string(.errorAccountNotManaged, email)
        case .missingBackupData(let number):
            return L10n.string(.errorMissingBackupData, number)
        case .missingCredentials(let number, let email):
            return L10n.string(.errorMissingCredentials, number, email)
        case .missingLiveCredentials(let number):
            return L10n.string(.errorMissingLiveCredentials, number)
        case .invalidBackupConfig(let number):
            return L10n.string(.errorInvalidBackupConfig, number)
        case .invalidSavedCredentials(let number):
            return L10n.string(.errorInvalidSavedCredentials, number)
        case .keychain(let message):
            return L10n.string(.errorKeychain, message)
        case .fileSystem(let message):
            return L10n.string(.errorFileSystem, message)
        }
    }
}

enum Timestamp {
    static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
