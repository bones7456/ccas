import Darwin
import Foundation

final class FileLock {
    private let path: URL
    private var descriptor: Int32 = -1
    private let logger = DebugLogger(category: "FileLock")

    init(path: URL) {
        self.path = path
    }

    func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        logger.notice("open lock")
        descriptor = open(path.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            logger.error("open lock failed")
            throw AccountSwitcherError.fileSystem(L10n.string(.errorCreateLock, path.path))
        }

        defer {
            logger.notice("release lock")
            flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }

        logger.notice("acquire lock")
        guard flock(descriptor, LOCK_EX) == 0 else {
            logger.error("acquire lock failed")
            throw AccountSwitcherError.fileSystem(L10n.string(.errorAcquireLock, path.path))
        }

        logger.notice("acquired lock")
        return try body()
    }
}
