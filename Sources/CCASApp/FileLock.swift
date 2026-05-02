import Darwin
import Foundation

final class FileLock {
    private let path: URL
    private var descriptor: Int32 = -1

    init(path: URL) {
        self.path = path
    }

    func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        descriptor = open(path.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw AccountSwitcherError.fileSystem(L10n.string(.errorCreateLock, path.path))
        }

        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }

        guard flock(descriptor, LOCK_EX) == 0 else {
            throw AccountSwitcherError.fileSystem(L10n.string(.errorAcquireLock, path.path))
        }

        return try body()
    }
}
