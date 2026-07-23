import Darwin
import Foundation

/// Detects running Claude Code instances by reading the PID files Claude Code
/// writes to `~/.claude/sessions/<pid>.json` (the same mechanism Claude Code
/// uses internally). CCAS switches the *global* `Claude Code-credentials`
/// Keychain entry and `~/.claude.json`, but a Claude Code process that is
/// already running holds its OAuth access token in memory and keeps billing the
/// account it launched with — it does not re-read the Keychain mid-task. So a
/// switch only takes effect for sessions started afterwards; this detector lets
/// the UI warn that any live session still bills the old account until restart.
///
/// Mirrors claude-swap's `process_detection.list_sessions`. CCAS never sets
/// `CLAUDE_CONFIG_DIR`, so the sessions directory is always `~/.claude/sessions`.
struct ClaudeProcessDetector {
    private let fileManager: FileManager
    private let home: URL

    init(
        fileManager: FileManager = .default,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.home = home
    }

    private var sessionsDirectory: URL {
        home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    /// Number of Claude Code sessions whose recorded PID is still alive.
    func runningInstanceCount() -> Int {
        runningPIDs().count
    }

    /// Live PIDs from `~/.claude/sessions/*.json`. Stale files (the process
    /// exited without cleanup) are skipped, so the count reflects reality.
    func runningPIDs() -> [Int32] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        var pids: [Int32] = []
        for url in entries where url.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: url),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let rawPID = object["pid"] as? Int,
                let pid = Int32(exactly: rawPID),
                Self.isProcessAlive(pid)
            else {
                continue
            }
            pids.append(pid)
        }
        return pids
    }

    /// Whether a process with the given PID is currently running.
    ///
    /// `kill(pid, 0)` sends no signal but performs the permission/existence
    /// checks: success means alive; `EPERM` means alive but owned by another
    /// user; `ESRCH` (and anything else) means gone.
    private static func isProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 1 else { return false }
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}
