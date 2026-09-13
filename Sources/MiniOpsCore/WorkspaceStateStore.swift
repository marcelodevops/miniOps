import Foundation

public struct IntegrationSettings: Codable, Equatable {
    public var jiraBaseURL: String
    public var jiraEmail: String
    public var githubUsername: String
    /// When enabled the embedded terminal attaches a Herdr session instead of a plain login shell.
    public var herdrModeEnabled: Bool
    public var ticketsPath: String

    public init(
        jiraBaseURL: String = "",
        jiraEmail: String = "",
        githubUsername: String = "",
        herdrModeEnabled: Bool = false,
        ticketsPath: String = ""
    ) {
        self.jiraBaseURL = jiraBaseURL
        self.jiraEmail = jiraEmail
        self.githubUsername = githubUsername
        self.herdrModeEnabled = herdrModeEnabled
        self.ticketsPath = ticketsPath
    }

    enum CodingKeys: String, CodingKey {
        case jiraBaseURL
        case jiraEmail
        case githubUsername
        case herdrModeEnabled
        case ticketsPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.jiraBaseURL = try container.decodeIfPresent(String.self, forKey: .jiraBaseURL) ?? ""
        self.jiraEmail = try container.decodeIfPresent(String.self, forKey: .jiraEmail) ?? ""
        self.githubUsername = try container.decodeIfPresent(String.self, forKey: .githubUsername) ?? ""
        self.herdrModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .herdrModeEnabled) ?? false
        self.ticketsPath = try container.decodeIfPresent(String.self, forKey: .ticketsPath) ?? ""
    }
}

/// When the last Jira ticket sync completed for a given workspace, successfully or not. Lets
/// the UI show a persistent "last synced"/"stale" indicator instead of only a transient status
/// message, scoped per workspace so syncing one workspace never overwrites another's freshness.
public struct JiraSyncStatus: Codable, Equatable {
    public var lastSyncDate: Date?
    public var lastSyncError: String?

    public init(lastSyncDate: Date? = nil, lastSyncError: String? = nil) {
        self.lastSyncDate = lastSyncDate
        self.lastSyncError = lastSyncError
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
    public var jiraSyncStatuses: [String: JiraSyncStatus] = [:]

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
        case jiraSyncStatuses
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
        self.jiraSyncStatuses = try container.decodeIfPresent([String: JiraSyncStatus].self, forKey: .jiraSyncStatuses) ?? [:]
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

    public func recordJiraSyncResult(workspacePath: String, date: Date, error: String?) {
        let stdPath = standardize(workspacePath)
        queue.sync {
            cachedState.jiraSyncStatuses[stdPath] = JiraSyncStatus(lastSyncDate: date, lastSyncError: error)
            persistToDisk()
        }
    }

    public func getJiraSyncStatus(workspacePath: String) -> JiraSyncStatus {
        let stdPath = standardize(workspacePath)
        return queue.sync {
            cachedState.jiraSyncStatuses[stdPath] ?? JiraSyncStatus()
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

    public func exportSettingsJSON() -> String? {
        queue.sync {
            let export = ExportedSettings(
                lastWorkspacePath: cachedState.lastWorkspacePath,
                hiddenRepoPaths: Array(cachedState.hiddenRepoPaths).sorted(),
                customRepoPaths: Array(cachedState.customRepoPaths).sorted(),
                integrationSettings: cachedState.integrationSettings,
                workspaceLayouts: cachedState.workspaceLayouts
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            guard let data = try? encoder.encode(export) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    public var backupStorageURL: URL {
        storageURL.deletingPathExtension().appendingPathExtension("bak.json")
    }

    @discardableResult
    public func backupState() -> Bool {
        queue.sync {
            guard let data = try? JSONEncoder().encode(cachedState) else { return false }
            do {
                try data.write(to: backupStorageURL, options: .atomic)
                return true
            } catch {
                return false
            }
        }
    }

    public func restoreBackup() -> (success: Bool, error: String?) {
        queue.sync {
            guard FileManager.default.fileExists(atPath: backupStorageURL.path),
                  let data = try? Data(contentsOf: backupStorageURL) else {
                return (false, "No backup file found at: \(backupStorageURL.path)")
            }
            do {
                let restored = try JSONDecoder().decode(PersistedAppState.self, from: data)
                cachedState = restored
                persistToDisk()
                return (true, nil)
            } catch {
                return (false, "Failed to decode backup state: \(error.localizedDescription)")
            }
        }
    }

    public func previewSettingsImport(_ jsonString: String) -> (preview: SettingsImportPreview?, error: String?) {
        guard let data = jsonString.data(using: .utf8) else {
            return (nil, "Invalid text encoding; expected UTF-8 JSON.")
        }
        let imported: ExportedSettings
        do {
            imported = try JSONDecoder().decode(ExportedSettings.self, from: data)
        } catch {
            return (nil, "Failed to parse settings JSON: \(error.localizedDescription)")
        }

        var validationErrors: [String] = []
        if let ws = imported.lastWorkspacePath, !ws.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (ws as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) || !isDir.boolValue {
                validationErrors.append("Workspace directory does not exist: \(ws)")
            }
        }

        let tp = imported.integrationSettings.ticketsPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tp.isEmpty {
            let expanded = (tp as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) || !isDir.boolValue {
                validationErrors.append("Tickets directory does not exist: \(tp)")
            }
        }

        for customRepo in imported.customRepoPaths {
            let expanded = (customRepo as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) || !isDir.boolValue {
                validationErrors.append("Custom repository does not exist: \(customRepo)")
            } else {
                let gitPath = (expanded as NSString).appendingPathComponent(".git")
                if !FileManager.default.fileExists(atPath: gitPath) {
                    validationErrors.append("Custom repository is not a git repository: \(customRepo)")
                }
            }
        }

        return queue.sync {
            var workspaceConflict: FieldConflict? = nil
            if let impWs = imported.lastWorkspacePath, !impWs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let stdImp = standardize(impWs)
                if let curWs = cachedState.lastWorkspacePath, !curWs.isEmpty, curWs != stdImp {
                    workspaceConflict = FieldConflict(field: "workspacePath", currentValue: curWs, importedValue: stdImp)
                }
            }

            let importedHidden = Set(imported.hiddenRepoPaths.map { standardize($0) })
            let newHidden = Array(importedHidden.subtracting(cachedState.hiddenRepoPaths)).sorted()
            let preservedHidden = Array(cachedState.hiddenRepoPaths).sorted()

            let importedCustom = Set(imported.customRepoPaths.map { standardize($0) })
            let newCustom = Array(importedCustom.subtracting(cachedState.customRepoPaths)).sorted()
            let preservedCustom = Array(cachedState.customRepoPaths).sorted()

            var integrationConflicts: [FieldConflict] = []
            var preservedIntegration: [String] = []

            func checkField(_ name: String, current: String, imported: String) {
                if !current.isEmpty && !imported.isEmpty && current != imported {
                    integrationConflicts.append(FieldConflict(field: name, currentValue: current, importedValue: imported))
                } else if !current.isEmpty {
                    preservedIntegration.append(name)
                }
            }

            checkField("jiraBaseURL", current: cachedState.integrationSettings.jiraBaseURL, imported: imported.integrationSettings.jiraBaseURL)
            checkField("jiraEmail", current: cachedState.integrationSettings.jiraEmail, imported: imported.integrationSettings.jiraEmail)
            checkField("githubUsername", current: cachedState.integrationSettings.githubUsername, imported: imported.integrationSettings.githubUsername)
            checkField("ticketsPath", current: cachedState.integrationSettings.ticketsPath, imported: imported.integrationSettings.ticketsPath)

            var layoutConflicts: [String] = []
            var newLayouts: [String] = []
            if let layouts = imported.workspaceLayouts {
                for (k, _) in layouts {
                    let stdK = standardize(k)
                    if cachedState.workspaceLayouts[stdK] != nil {
                        layoutConflicts.append(stdK)
                    } else {
                        newLayouts.append(stdK)
                    }
                }
            }

            let hasConflicts = workspaceConflict != nil || !integrationConflicts.isEmpty || !layoutConflicts.isEmpty

            let preview = SettingsImportPreview(
                workspaceConflict: workspaceConflict,
                newHiddenRepos: newHidden,
                preservedHiddenRepos: preservedHidden,
                newCustomRepos: newCustom,
                preservedCustomRepos: preservedCustom,
                integrationConflicts: integrationConflicts,
                preservedIntegrationFields: preservedIntegration,
                layoutConflicts: layoutConflicts.sorted(),
                newLayouts: newLayouts.sorted(),
                hasConflicts: hasConflicts,
                validationErrors: validationErrors
            )
            return (preview, nil)
        }
    }

    public func importSettingsJSON(
        _ jsonString: String,
        overwriteConflicts: Bool = false
    ) -> (success: Bool, error: String?, preview: SettingsImportPreview?) {
        let (previewOpt, parseErr) = previewSettingsImport(jsonString)
        if let err = parseErr {
            return (false, err, nil)
        }
        guard let preview = previewOpt else {
            return (false, "Failed to generate import preview.", nil)
        }
        if !preview.validationErrors.isEmpty {
            return (false, preview.validationErrors.joined(separator: "; "), preview)
        }

        guard let data = jsonString.data(using: .utf8),
              let imported = try? JSONDecoder().decode(ExportedSettings.self, from: data) else {
            return (false, "Failed to decode settings.", preview)
        }

        // Back up destination state before applying any mutations!
        _ = backupState()

        queue.sync {
            // Workspace path: preserve existing if non-empty, unless overwriteConflicts is requested
            if let ws = imported.lastWorkspacePath, !ws.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let stdWs = standardize(ws)
                if overwriteConflicts || cachedState.lastWorkspacePath == nil || cachedState.lastWorkspacePath?.isEmpty == true {
                    cachedState.lastWorkspacePath = stdWs
                }
            }

            // Repositories: preserve existing by default through union
            let importedHidden = Set(imported.hiddenRepoPaths.map { standardize($0) })
            let importedCustom = Set(imported.customRepoPaths.map { standardize($0) })
            if overwriteConflicts {
                cachedState.hiddenRepoPaths = importedHidden
                cachedState.customRepoPaths = importedCustom
            } else {
                cachedState.hiddenRepoPaths.formUnion(importedHidden)
                cachedState.customRepoPaths.formUnion(importedCustom)
            }

            // Integration settings: preserve existing non-empty values by default
            if overwriteConflicts {
                cachedState.integrationSettings = imported.integrationSettings
            } else {
                if cachedState.integrationSettings.jiraBaseURL.isEmpty {
                    cachedState.integrationSettings.jiraBaseURL = imported.integrationSettings.jiraBaseURL
                }
                if cachedState.integrationSettings.jiraEmail.isEmpty {
                    cachedState.integrationSettings.jiraEmail = imported.integrationSettings.jiraEmail
                }
                if cachedState.integrationSettings.githubUsername.isEmpty {
                    cachedState.integrationSettings.githubUsername = imported.integrationSettings.githubUsername
                }
                if cachedState.integrationSettings.ticketsPath.isEmpty {
                    cachedState.integrationSettings.ticketsPath = imported.integrationSettings.ticketsPath
                }
                if !cachedState.integrationSettings.herdrModeEnabled && imported.integrationSettings.herdrModeEnabled {
                    cachedState.integrationSettings.herdrModeEnabled = true
                }
            }

            // Layouts: preserve existing by default on conflict
            if let layouts = imported.workspaceLayouts {
                for (k, v) in layouts {
                    let stdK = standardize(k)
                    if overwriteConflicts || cachedState.workspaceLayouts[stdK] == nil {
                        cachedState.workspaceLayouts[stdK] = v
                    }
                }
            }

            persistToDisk()
        }

        return (true, nil, preview)
    }

    public func importSettingsJSON(_ jsonString: String) -> (success: Bool, error: String?) {
        let res = importSettingsJSON(jsonString, overwriteConflicts: false)
        return (res.success, res.error)
    }

    public func auditSettings() -> [String] {
        queue.sync {
            var warnings: [String] = []
            if let ws = cachedState.lastWorkspacePath, !ws.isEmpty {
                let expanded = (ws as NSString).expandingTildeInPath
                var isDir: ObjCBool = false
                if !FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) || !isDir.boolValue {
                    warnings.append("Workspace directory missing or not a directory: \(ws)")
                }
            }
            let tp = cachedState.integrationSettings.ticketsPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tp.isEmpty {
                let expanded = (tp as NSString).expandingTildeInPath
                var isDir: ObjCBool = false
                if !FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) || !isDir.boolValue {
                    warnings.append("Configured tickets directory missing or not a directory: \(tp)")
                }
            }
            for customRepo in cachedState.customRepoPaths {
                let expanded = (customRepo as NSString).expandingTildeInPath
                let gitPath = (expanded as NSString).appendingPathComponent(".git")
                if !FileManager.default.fileExists(atPath: gitPath) {
                    warnings.append("Custom repository missing .git: \(customRepo)")
                }
            }
            return warnings
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

public struct ExportedSettings: Codable, Equatable {
    public var lastWorkspacePath: String?
    public var hiddenRepoPaths: [String]
    public var customRepoPaths: [String]
    public var integrationSettings: IntegrationSettings
    public var workspaceLayouts: [String: WorkbenchLayoutState]?

    public init(
        lastWorkspacePath: String? = nil,
        hiddenRepoPaths: [String] = [],
        customRepoPaths: [String] = [],
        integrationSettings: IntegrationSettings = IntegrationSettings(),
        workspaceLayouts: [String: WorkbenchLayoutState]? = nil
    ) {
        self.lastWorkspacePath = lastWorkspacePath
        self.hiddenRepoPaths = hiddenRepoPaths
        self.customRepoPaths = customRepoPaths
        self.integrationSettings = integrationSettings
        self.workspaceLayouts = workspaceLayouts
    }
}

public struct FieldConflict: Sendable, Codable, Equatable {
    public let field: String
    public let currentValue: String
    public let importedValue: String

    public init(field: String, currentValue: String, importedValue: String) {
        self.field = field
        self.currentValue = currentValue
        self.importedValue = importedValue
    }
}

public struct SettingsImportPreview: Sendable, Codable, Equatable {
    public var workspaceConflict: FieldConflict?
    public var newHiddenRepos: [String]
    public var preservedHiddenRepos: [String]
    public var newCustomRepos: [String]
    public var preservedCustomRepos: [String]
    public var integrationConflicts: [FieldConflict]
    public var preservedIntegrationFields: [String]
    public var layoutConflicts: [String]
    public var newLayouts: [String]
    public var hasConflicts: Bool
    public var validationErrors: [String]

    public init(
        workspaceConflict: FieldConflict? = nil,
        newHiddenRepos: [String] = [],
        preservedHiddenRepos: [String] = [],
        newCustomRepos: [String] = [],
        preservedCustomRepos: [String] = [],
        integrationConflicts: [FieldConflict] = [],
        preservedIntegrationFields: [String] = [],
        layoutConflicts: [String] = [],
        newLayouts: [String] = [],
        hasConflicts: Bool = false,
        validationErrors: [String] = []
    ) {
        self.workspaceConflict = workspaceConflict
        self.newHiddenRepos = newHiddenRepos
        self.preservedHiddenRepos = preservedHiddenRepos
        self.newCustomRepos = newCustomRepos
        self.preservedCustomRepos = preservedCustomRepos
        self.integrationConflicts = integrationConflicts
        self.preservedIntegrationFields = preservedIntegrationFields
        self.layoutConflicts = layoutConflicts
        self.newLayouts = newLayouts
        self.hasConflicts = hasConflicts
        self.validationErrors = validationErrors
    }
}
