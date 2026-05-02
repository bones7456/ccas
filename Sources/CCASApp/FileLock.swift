import Darwin
import Foundation
import OSLog

final class FileLock {
    private let path: URL
    private var descriptor: Int32 = -1
    private let logger = Logger(subsystem: "dev.local.ccas", category: "FileLock")

    init(path: URL) {
        self.path = path
    }

    func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        logger.notice("open lock path=\(self.path.path, privacy: .public)")
        descriptor = open(path.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            logger.error("open lock failed path=\(self.path.path, privacy: .public)")
            throw AccountSwitcherError.fileSystem(L10n.string(.errorCreateLock, path.path))
        }

        defer {
            logger.notice("release lock path=\(self.path.path, privacy: .public)")
            flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }

        logger.notice("acquire lock path=\(self.path.path, privacy: .public)")
        guard flock(descriptor, LOCK_EX) == 0 else {
            logger.error("acquire lock failed path=\(self.path.path, privacy: .public)")
            throw AccountSwitcherError.fileSystem(L10n.string(.errorAcquireLock, path.path))
        }

        logger.notice("acquired lock path=\(self.path.path, privacy: .public)")
        return try body()
    }
}
