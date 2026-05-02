import Foundation

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
    case invalidBackupConfig(Int)
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
        case .invalidBackupConfig(let number):
            return L10n.string(.errorInvalidBackupConfig, number)
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
