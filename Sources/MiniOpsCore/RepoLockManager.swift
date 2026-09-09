import Foundation

public enum RepoLockError: Error, LocalizedError {
    case invalidPath(String)
    case repositoryBusy(String)
    case cannotCancelRunningOperation(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "Invalid repository path: \(path)"
        case .repositoryBusy(let repo):
            return "Repository busy: wait for its current action to finish: \(repo)"
        case .cannotCancelRunningOperation(let repo):
            return "Cannot cancel running operation safely for repository: \(repo)"
        }
    }
}

public final class RepoLockManager: @unchecked Sendable {
    public static let shared = RepoLockManager()

    public final class Lease {
        public let repoKey: String
        public internal(set) var ownerThreadId: UInt64?
        public internal(set) var depth: Int = 0
        public internal(set) var acquiredAt: Date = Date()
        public internal(set) var isCancelled: Bool = false

        init(repoKey: String) {
            self.repoKey = repoKey
        }
    }

    private let lock = NSLock()
    private var leases: [String: Lease] = [:]
    private var activeOperations: [String: String] = [:] // repoKey -> actionDescription

    public init() {}

    public static func normalizeRepoPath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("\0") {
            return nil
        }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardized
        return url.path
    }

    private func currentThreadId() -> UInt64 {
        var threadId: UInt64 = 0
        pthread_threadid_np(nil, &threadId)
        return threadId
    }

    public func tryAcquire(repoPath: String, action: String = "mutation") throws -> String {
        guard let key = Self.normalizeRepoPath(repoPath) else {
            throw RepoLockError.invalidPath(repoPath)
        }

        lock.lock()
        defer { lock.unlock() }

        let tid = currentThreadId()
        let lease = leases[key] ?? Lease(repoKey: key)
        leases[key] = lease

        if lease.depth <= 0 {
            lease.ownerThreadId = tid
            lease.depth = 1
            lease.acquiredAt = Date()
            lease.isCancelled = false
            activeOperations[key] = action
            return key
        } else if lease.ownerThreadId == tid {
            lease.depth += 1
            return key
        } else {
            throw RepoLockError.repositoryBusy(key)
        }
    }

    public func release(repoKey: String) {
        lock.lock()
        defer { lock.unlock() }

        let tid = currentThreadId()
        guard let lease = leases[repoKey], lease.ownerThreadId == tid, lease.depth > 0 else {
            return
        }

        lease.depth -= 1
        if lease.depth == 0 {
            lease.ownerThreadId = nil
            activeOperations.removeValue(forKey: repoKey)
        }
    }

    public func withRepoLock<T>(repoPath: String, action: String = "mutation", block: () throws -> T) throws -> T {
        let key = try tryAcquire(repoPath: repoPath, action: action)
        defer {
            release(repoKey: key)
        }
        return try block()
    }

    public func cancelOperation(repoPath: String) -> (cancelled: Bool, message: String) {
        guard let key = Self.normalizeRepoPath(repoPath) else {
            return (false, "Invalid repository path")
        }

        lock.lock()
        defer { lock.unlock() }

        guard let lease = leases[key], lease.depth > 0 else {
            return (false, "No active operation running for repository")
        }

        // A running operation cannot simply be released or abandoned without safe process termination.
        // We record the cancel intention, but do not release the lease while it is still running!
        lease.isCancelled = true
        return (false, "Operation is running and cannot be safely interrupted mid-execution; lock preserved")
    }

    public func isBusy(repoPath: String) -> Bool {
        guard let key = Self.normalizeRepoPath(repoPath) else { return false }
        lock.lock()
        defer { lock.unlock() }
        if let lease = leases[key] {
            return lease.depth > 0
        }
        return false
    }
}
