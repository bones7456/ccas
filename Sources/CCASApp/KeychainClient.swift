import Foundation

struct KeychainPasswordItem {
    var account: String
    var password: String
}

final class KeychainClient {
    private struct SecurityCommandResult {
        var terminationStatus: Int32
        var output: Data
        var error: Data
    }

    private struct GenericPasswordMetadata {
        var found: Bool
        var account: String?
    }

    private static let securityExecutable = URL(fileURLWithPath: "/usr/bin/security")
    private let logger = DebugLogger(category: "Keychain")

    func readGenericPasswordItem(service: String) throws -> KeychainPasswordItem? {
        let metadata = try genericPasswordMetadata(service: service)
        guard metadata.found else {
            return nil
        }

        guard let password = try readGenericPassword(service: service, account: metadata.account) else {
            return nil
        }

        return KeychainPasswordItem(
            account: metadata.account?.isEmpty == false ? metadata.account! : NSUserName(),
            password: password
        )
    }

    func readGenericPassword(service: String, account: String? = nil) throws -> String? {
        var arguments = ["find-generic-password", "-s", service, "-w"]
        if let account {
            arguments.insert(contentsOf: ["-a", account], at: 1)
        }

        let result = try runSecurity(arguments)
        if Self.isNotFound(result) {
            return nil
        }

        guard result.terminationStatus == 0 else {
            let message = Self.message(for: result)
            logger.error("read password failed service=\(service) status=\(result.terminationStatus) message=\(message)")
            throw AccountSwitcherError.keychain(message)
        }

        return Self.passwordString(from: result.output)
    }

    func upsertGenericPassword(service: String, account: String, password: String) throws {
        guard let data = password.data(using: .utf8) else {
            throw AccountSwitcherError.keychain(L10n.string(.errorCredentialEncoding))
        }

        let removed = try removeAllMatching(service: service, account: account)
        if removed > 1 {
            logger.notice("cleaned duplicate keychain entries service=\(service) count=\(removed)")
        }

        let result = try runSecurity([
            "add-generic-password",
            "-s", service,
            "-a", account,
            "-X", Self.hexString(from: data)
        ])

        guard result.terminationStatus == 0 else {
            let message = Self.message(for: result)
            logger.error("upsert password failed service=\(service) status=\(result.terminationStatus) message=\(message)")
            throw AccountSwitcherError.keychain(message)
        }
    }

    func upsertGenericPasswordForService(service: String, fallbackAccount: String, password: String) throws {
        guard let data = password.data(using: .utf8) else {
            throw AccountSwitcherError.keychain(L10n.string(.errorCredentialEncoding))
        }

        let metadata = try genericPasswordMetadata(service: service)
        let account = metadata.found ? (metadata.account ?? "") : fallbackAccount

        let removed = try removeAllMatching(service: service, account: account)
        if removed > 1 {
            logger.notice("cleaned duplicate keychain entries service=\(service) count=\(removed)")
        }

        let result = try runSecurity([
            "add-generic-password",
            "-s", service,
            "-a", account,
            "-X", Self.hexString(from: data)
        ])

        guard result.terminationStatus == 0 else {
            let message = Self.message(for: result)
            logger.error("upsert password failed service=\(service) status=\(result.terminationStatus) message=\(message)")
            throw AccountSwitcherError.keychain(message)
        }
    }

    @discardableResult
    func removeAllMatching(service: String, account: String) throws -> Int {
        var removed = 0
        while true {
            let result = try runSecurity([
                "delete-generic-password",
                "-s", service,
                "-a", account
            ])

            if Self.isNotFound(result) {
                return removed
            }

            guard result.terminationStatus == 0 else {
                let message = Self.message(for: result)
                logger.error("remove duplicates failed service=\(service) status=\(result.terminationStatus) message=\(message)")
                throw AccountSwitcherError.keychain(message)
            }

            removed += 1
            if removed > 64 {
                logger.error("remove duplicates aborted service=\(service) afterCount=\(removed)")
                return removed
            }
        }
    }

    func deleteGenericPassword(service: String, account: String) throws {
        let result = try runSecurity([
            "delete-generic-password",
            "-s", service,
            "-a", account
        ])

        if result.terminationStatus == 0 || Self.isNotFound(result) {
            return
        }

        let message = Self.message(for: result)
        logger.error("delete password failed service=\(service) status=\(result.terminationStatus) message=\(message)")
        throw AccountSwitcherError.keychain(message)
    }

    private func genericPasswordMetadata(service: String) throws -> GenericPasswordMetadata {
        let result = try runSecurity([
            "find-generic-password",
            "-s", service
        ])

        if Self.isNotFound(result) {
            return GenericPasswordMetadata(found: false, account: nil)
        }

        guard result.terminationStatus == 0 else {
            let message = Self.message(for: result)
            logger.error("read metadata failed service=\(service) status=\(result.terminationStatus) message=\(message)")
            throw AccountSwitcherError.keychain(message)
        }

        let account = Self.account(from: result.output)
        return GenericPasswordMetadata(found: true, account: account)
    }

    private func runSecurity(_ arguments: [String]) throws -> SecurityCommandResult {
        let process = Process()
        process.executableURL = Self.securityExecutable
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw AccountSwitcherError.keychain("Unable to run security: \(error.localizedDescription)")
        }

        process.waitUntilExit()

        return SecurityCommandResult(
            terminationStatus: process.terminationStatus,
            output: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            error: errorPipe.fileHandleForReading.readDataToEndOfFile()
        )
    }

    private static func account(from data: Data) -> String? {
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line).trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("\"acct\"<blob>=") else {
                continue
            }

            let value = String(text.dropFirst("\"acct\"<blob>=".count))
            if value == "<NULL>" {
                return nil
            }
            return unquotedAttributeValue(value)
        }

        return nil
    }

    private static func unquotedAttributeValue(_ value: String) -> String? {
        guard value.hasPrefix("\""), value.hasSuffix("\"") else {
            return value.isEmpty ? nil : value
        }

        let inner = value.dropFirst().dropLast()
        var result = ""
        var isEscaped = false

        for character in inner {
            if isEscaped {
                result.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else {
                result.append(character)
            }
        }

        if isEscaped {
            result.append("\\")
        }

        return result
    }

    private static func passwordString(from data: Data) -> String? {
        var bytes = [UInt8](data)
        if bytes.last == 0x0A {
            bytes.removeLast()
            if bytes.last == 0x0D {
                bytes.removeLast()
            }
        }
        let trimmed = Data(bytes)

        if let decoded = decodedFromHexOutput(trimmed) {
            return decoded
        }
        return String(data: trimmed, encoding: .utf8)
    }

    // `/usr/bin/security ... -w` prints the password as lowercase hex (no
    // `0x` prefix) whenever the stored bytes include anything outside the
    // printable ASCII range 0x20–0x7E. Claude Code pretty-prints its
    // credentials JSON, so the embedded newlines trigger that path.
    private static func decodedFromHexOutput(_ data: Data) -> String? {
        guard data.count >= 2, data.count % 2 == 0 else {
            return nil
        }

        var decoded = Data(capacity: data.count / 2)
        var high: UInt8 = 0
        var haveHigh = false

        for byte in data {
            let nibble: UInt8
            switch byte {
            case 0x30...0x39: nibble = byte - 0x30
            case 0x61...0x66: nibble = byte - 0x61 + 10
            case 0x41...0x46: nibble = byte - 0x41 + 10
            default: return nil
            }

            if haveHigh {
                decoded.append((high << 4) | nibble)
                haveHigh = false
            } else {
                high = nibble
                haveHigh = true
            }
        }

        return String(data: decoded, encoding: .utf8)
    }

    private static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func isNotFound(_ result: SecurityCommandResult) -> Bool {
        if result.terminationStatus == 44 {
            return true
        }

        let message = message(for: result).lowercased()
        return message.contains("could not be found")
            || message.contains("specified item could not be found")
    }

    private static func message(for result: SecurityCommandResult) -> String {
        let error = String(data: result.error, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !error.isEmpty {
            return error
        }

        let output = String(data: result.output, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !output.isEmpty {
            return output
        }

        return "security exited with status \(result.terminationStatus)"
    }
}
