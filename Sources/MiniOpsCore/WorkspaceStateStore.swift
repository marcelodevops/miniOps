import Foundation

public struct PersistedAppState: Codable {
    public var lastWorkspacePath: String?
    public var lastSelectedRepoPath: String?
    public var repoStates: [String: RepoLayoutState]

    public init(
        lastWorkspacePath: String? = nil,
        lastSelectedRepoPath: String? = nil,
        repoStates: [String: RepoLayoutState] = [:]
    ) {
        self.lastWorkspacePath = lastWorkspacePath
        self.lastSelectedRepoPath = lastSelectedRepoPath
        self.repoStates = repoStates
    }
}

public final class WorkspaceStateStore: @unchecked Sendable {
    public static let shared = WorkspaceStateStore()

    private let storageURL: URL
    private let queue = DispatchQueue(label: "miniops.state.store")
    private var cachedState: PersistedAppState

    public init(customStorageURL: URL? = nil) {
        if let customURL = customStorageURL {
            self.storageURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let miniOpsDir = appSupport.appendingPathComponent("miniOps", isDirectory: true)
            try? FileManager.default.createDirectory(at: miniOpsDir, withIntermediateDirectories: true)
            self.storageURL = miniOpsDir.appendingPathComponent("state.json")
        }

        if let data = try? Data(contentsOf: self.storageURL),
           let state = try? JSONDecoder().decode(PersistedAppState.self, from: data) {
            self.cachedState = state
        } else {
            self.cachedState = PersistedAppState()
        }
    }

    public func getAppState() -> PersistedAppState {
        queue.sync { cachedState }
    }

    public func getRepoState(repoPath: String) -> RepoLayoutState {
        queue.sync {
            cachedState.repoStates[repoPath] ?? RepoLayoutState()
        }
    }

    public func saveRepoState(repoPath: String, state: RepoLayoutState) {
        queue.sync {
            cachedState.repoStates[repoPath] = state
            cachedState.lastSelectedRepoPath = repoPath
            persistToDisk()
        }
    }

    public func saveWorkspacePath(_ path: String) {
        queue.sync {
            cachedState.lastWorkspacePath = path
            persistToDisk()
        }
    }

    private func persistToDisk() {
        guard let data = try? JSONEncoder().encode(cachedState) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
