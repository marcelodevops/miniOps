import Foundation

public struct IntegrationSettings: Codable, Equatable {
    public var jiraBaseURL: String
    public var jiraEmail: String
    public var githubUsername: String
    /// When enabled the embedded terminal attaches a Herdr session instead of a plain login shell.
    public var herdrModeEnabled: Bool

    public init(
        jiraBaseURL: String = "",
        jiraEmail: String = "",
        githubUsername: String = "",
        herdrModeEnabled: Bool = false
    ) {
        self.jiraBaseURL = jiraBaseURL
        self.jiraEmail = jiraEmail
        self.githubUsername = githubUsername
        self.herdrModeEnabled = herdrModeEnabled
    }

    enum CodingKeys: String, CodingKey {
        case jiraBaseURL
        case jiraEmail
        case githubUsername
        case herdrModeEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.jiraBaseURL = try container.decodeIfPresent(String.self, forKey: .jiraBaseURL) ?? ""
        self.jiraEmail = try container.decodeIfPresent(String.self, forKey: .jiraEmail) ?? ""
        self.githubUsername = try container.decodeIfPresent(String.self, forKey: .githubUsername) ?? ""
        self.herdrModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .herdrModeEnabled) ?? false
    }
}

public struct PersistedAppState: Codable {
    public var lastWorkspacePath: String?
    public var lastSelectedRepoPath: String?
    public var repoStates: [String: RepoLayoutState]
    public var hiddenRepoPaths: Set<String>
    public var customRepoPaths: Set<String>
    public var integrationSettings: IntegrationSettings
    public var workspaceLayouts: [String: WorkbenchLayoutState] = [:]
    public var workbenchLayout: WorkbenchLayoutState

    public init(
        lastWorkspacePath: String? = nil,
        lastSelectedRepoPath: String? = nil,
        repoStates: [String: RepoLayoutState] = [:],
        hiddenRepoPaths: Set<String> = [],
        customRepoPaths: Set<String> = [],
        integrationSettings: IntegrationSettings = IntegrationSettings(),
        workbenchLayout: WorkbenchLayoutState = WorkbenchLayoutState()
    ) {
        self.lastWorkspacePath = lastWorkspacePath
        self.lastSelectedRepoPath = lastSelectedRepoPath
        self.repoStates = repoStates
        self.hiddenRepoPaths = hiddenRepoPaths
        self.customRepoPaths = customRepoPaths
        self.integrationSettings = integrationSettings
        self.workbenchLayout = workbenchLayout
    }

    enum CodingKeys: String, CodingKey {
        case lastWorkspacePath
        case lastSelectedRepoPath
        case repoStates
        case hiddenRepoPaths
        case customRepoPaths
        case integrationSettings
        case workspaceLayouts
        case workbenchLayout
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.lastWorkspacePath = try container.decodeIfPresent(String.self, forKey: .lastWorkspacePath)
        self.lastSelectedRepoPath = try container.decodeIfPresent(String.self, forKey: .lastSelectedRepoPath)
        self.repoStates = try container.decodeIfPresent([String: RepoLayoutState].self, forKey: .repoStates) ?? [:]
        self.hiddenRepoPaths = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenRepoPaths) ?? []
        self.customRepoPaths = try container.decodeIfPresent(Set<String>.self, forKey: .customRepoPaths) ?? []
        self.integrationSettings = try container.decodeIfPresent(IntegrationSettings.self, forKey: .integrationSettings) ?? IntegrationSettings()
        self.workspaceLayouts = try container.decodeIfPresent([String: WorkbenchLayoutState].self, forKey: .workspaceLayouts) ?? [:]
        self.workbenchLayout = try container.decodeIfPresent(WorkbenchLayoutState.self, forKey: .workbenchLayout) ?? WorkbenchLayoutState()
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
        let stdPath = standardize(path)
        queue.sync {
            cachedState.lastWorkspacePath = stdPath
            persistToDisk()
        }
    }

    public func hideRepo(path: String) {
        let stdPath = standardize(path)
        queue.sync {
            cachedState.hiddenRepoPaths.insert(stdPath)
            persistToDisk()
        }
    }

    public func unhideRepo(path: String) {
        let stdPath = standardize(path)
        queue.sync {
            cachedState.hiddenRepoPaths.remove(stdPath)
            persistToDisk()
        }
    }

    public func unhideAllRepos() {
        queue.sync {
            cachedState.hiddenRepoPaths.removeAll()
            persistToDisk()
        }
    }

    public func getHiddenRepoPaths() -> Set<String> {
        queue.sync { cachedState.hiddenRepoPaths }
    }

    public func addCustomRepo(path: String) {
        let stdPath = standardize(path)
        queue.sync {
            cachedState.customRepoPaths.insert(stdPath)
            cachedState.hiddenRepoPaths.remove(stdPath)
            persistToDisk()
        }
    }

    public func removeCustomRepo(path: String) {
        let stdPath = standardize(path)
        queue.sync {
            cachedState.customRepoPaths.remove(stdPath)
            persistToDisk()
        }
    }

    public func getCustomRepoPaths() -> Set<String> {
        queue.sync { cachedState.customRepoPaths }
    }

    public func getIntegrationSettings() -> IntegrationSettings {
        queue.sync { cachedState.integrationSettings }
    }

    public func saveIntegrationSettings(_ settings: IntegrationSettings) {
        queue.sync {
            cachedState.integrationSettings = settings
            persistToDisk()
        }
    }

    public func setHerdrModeEnabled(_ enabled: Bool) {
        queue.sync {
            cachedState.integrationSettings.herdrModeEnabled = enabled
            persistToDisk()
        }
    }

    public func getWorkbenchLayout(workspacePath: String? = nil) -> WorkbenchLayoutState {
        queue.sync {
            guard let path = workspacePath else { return cachedState.workbenchLayout }
            if let layout = cachedState.workspaceLayouts[standardize(path)] { return layout }
            // Migrate the legacy global layout only to its original workspace.
            if cachedState.workspaceLayouts.isEmpty,
               let previous = cachedState.lastWorkspacePath,
               standardize(previous) == standardize(path) { return cachedState.workbenchLayout }
            return WorkbenchLayoutState()
        }
    }

    public func saveWorkbenchLayout(_ layout: WorkbenchLayoutState, workspacePath: String? = nil) {
        queue.sync {
            if let path = workspacePath {
                cachedState.workspaceLayouts[standardize(path)] = layout
            } else {
                cachedState.workbenchLayout = layout
            }
            persistToDisk()
        }
    }

    private func standardize(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardized.path
    }

    private func persistToDisk() {
        guard let data = try? JSONEncoder().encode(cachedState) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
