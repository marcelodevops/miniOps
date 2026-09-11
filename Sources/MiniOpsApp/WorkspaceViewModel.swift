import SwiftUI
import AppKit
import MiniOpsCore

@MainActor
public final class WorkspaceViewModel: ObservableObject {
    @Published public var workspacePath: String = ""
    @Published public var repositories: [RepoInfo] = []
    @Published public var selectedRepo: RepoInfo?

    // File navigation & editor state
    @Published public var fileTree: FileNode?
    @Published public var selectedFilePath: String?
    @Published public var fileContent: String = ""
    @Published public var isEditorModified: Bool = false

    // Layout & split state for active repo
    @Published public var expandedFolderPaths: Set<String> = []
    @Published public var terminalRatio: Double = 0.5
    @Published public var isEditorCollapsed: Bool = false
    @Published public var isTerminalCollapsed: Bool = false
    @Published public var isGitInspectorOpen: Bool = false

    // Git changes state
    @Published public var selectedFilesForCommit: Set<String> = [] {
        didSet {
            guard let repo = selectedRepo, oldValue != selectedFilesForCommit else { return }
            var state = stateStore.getRepoState(repoPath: repo.path)
            state.selectedFilesForCommit = selectedFilesForCommit
            stateStore.saveRepoState(repoPath: repo.path, state: state)
        }
    }
    @Published public var activeDiffFile: String? = nil
    @Published public var activeAgents: [AgentInfo] = []
    @Published public var tickets: [TicketInfo] = []
    @Published public var isSyncingTickets: Bool = false
    @Published public var ticketSyncStatus: String? = nil
    @Published public var graphData: GraphifyData? = nil
    @Published public var workbenchLayout: WorkbenchLayoutState = WorkbenchLayoutState() {
        didSet {
            // Drag gestures persist their dimensions once, when the drag ends.
            var previous = oldValue
            previous.leftDockWidth = workbenchLayout.leftDockWidth
            previous.rightDockWidth = workbenchLayout.rightDockWidth
            previous.bottomDockHeightRatio = workbenchLayout.bottomDockHeightRatio
            if !workspacePath.isEmpty && previous != workbenchLayout { saveWorkbenchLayout() }
        }
    }
    private var previouslyNotifiedWaitingPIDs: Set<Int> = []
    private let agentScanner = AgentScanner.shared

    @Published public var isScanning = false
    @Published public var isShowingCloneSheet: Bool = false
    @Published public var isShowingSettingsSheet: Bool = false
    @Published public var hiddenRepoPaths: Set<String> = []
    private var scanGeneration = 0
    private var loadedFileContent: String = ""

    private let scanner = WorkspaceScanner.shared
    private let gitService = GitService.shared
    private let fileSystem = FileSystemService.shared
    private let stateStore = WorkspaceStateStore.shared

    public init() {
        let appState = stateStore.getAppState()
        self.hiddenRepoPaths = stateStore.getHiddenRepoPaths()
        let initialWorkspace = appState.lastWorkspacePath ?? "~/repos"
        setWorkspace(path: initialWorkspace)

        setupNotificationListeners()
    }

    public func setWorkspace(path: String) {
        guard confirmLeavingEditor() else { return }
        if selectedRepo != nil { saveCurrentRepoLayout() }
        selectedRepo = nil
        selectedFilePath = nil
        fileContent = ""
        fileTree = nil
        let expanded = (path as NSString).expandingTildeInPath
        let layout = stateStore.getWorkbenchLayout(workspacePath: expanded)
        self.workspacePath = expanded
        self.workbenchLayout = layout
        saveWorkbenchLayout()
        stateStore.saveWorkspacePath(expanded)
        refreshRepositories()
    }

    public func refreshRepositories() {
        guard !workspacePath.isEmpty else { return }
        scanGeneration += 1
        let generation = scanGeneration
        let path = workspacePath
        isScanning = true
        let customPaths = stateStore.getCustomRepoPaths()
        DispatchQueue.global(qos: .userInitiated).async { [scanner] in
            let allScanned = scanner.scan(rootPath: path, customPaths: customPaths)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.scanGeneration == generation else { return }
                self.hiddenRepoPaths = self.stateStore.getHiddenRepoPaths()
                let visibleRepos = allScanned.filter { !self.hiddenRepoPaths.contains($0.path) }
                self.repositories = visibleRepos
                self.isScanning = false
                if let current = self.selectedRepo,
                   let updated = visibleRepos.first(where: { $0.path == current.path }) {
                    self.selectedRepo = updated
                } else if self.selectedRepo == nil || !visibleRepos.contains(where: { $0.path == self.selectedRepo?.path }) {
                    let saved = self.stateStore.getAppState().lastSelectedRepoPath
                    if let repo = visibleRepos.first(where: { $0.path == saved }) ?? visibleRepos.first {
                        self.performSelectRepo(repo)
                    } else {
                        self.selectedRepo = nil
                        self.selectedFilePath = nil
                        self.fileContent = ""
                        self.fileTree = nil
                    }
                }
                self.refreshAgents()
                self.refreshTickets()
                self.syncJiraTickets()
                self.refreshGraph()
            }
        }
    }

    public func selectRepo(_ repo: RepoInfo) {
        guard repo.path != selectedRepo?.path, confirmLeavingEditor() else { return }
        performSelectRepo(repo)
    }

    public func confirmLeavingEditor() -> Bool {
        guard isEditorModified else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes before continuing?"
        alert.informativeText = URL(fileURLWithPath: selectedFilePath ?? "file").lastPathComponent
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Changes")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveCurrentFile()
        case .alertThirdButtonReturn:
            fileContent = loadedFileContent
            isEditorModified = false
            return true
        default: return false
        }
    }

    private func showFileError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    private func performSelectRepo(_ repo: RepoInfo) {
        // Save current repo's layout before switching
        if selectedRepo != nil {
            saveCurrentRepoLayout()
        }

        selectedRepo = repo
        fileTree = fileSystem.buildFileTree(for: repo.path)

        // Restore saved layout state for this repo
        let state = stateStore.getRepoState(repoPath: repo.path)
        self.terminalRatio = state.terminalHeightRatio
        self.expandedFolderPaths = state.expandedFolderPaths
        self.isEditorCollapsed = state.isEditorCollapsed
        self.isTerminalCollapsed = state.isTerminalCollapsed
        self.isGitInspectorOpen = state.isGitInspectorOpen

        // Restore file selection: resolve relative or absolute path within repo
        if let storedPath = state.selectedFilePath {
            let resolved = (storedPath as NSString).isAbsolutePath ? storedPath : (repo.path as NSString).appendingPathComponent(storedPath)
            if FileManager.default.fileExists(atPath: resolved) {
                _ = loadFile(filePath: resolved)
            } else {
                selectedFilePath = nil
                fileContent = ""
                isEditorModified = false
            }
        } else {
            selectedFilePath = nil
            fileContent = ""
            isEditorModified = false
        }

        // Restore commit file selection: preserve excluded files if user previously customized selection
        let currentChanged = Set(repo.changedFiles.map { $0.path })
        if let savedSelection = state.selectedFilesForCommit {
            self.selectedFilesForCommit = savedSelection.intersection(currentChanged)
        } else {
            self.selectedFilesForCommit = currentChanged
        }

        // Restore or default active diff file
        if let active = activeDiffFile, !currentChanged.contains(active) {
            activeDiffFile = repo.changedFiles.first?.path
        } else if activeDiffFile == nil {
            activeDiffFile = repo.changedFiles.first?.path
        }

        refreshGraph()
        refreshTickets()
    }

    @discardableResult
    public func selectFile(_ path: String) -> Bool {
        guard confirmLeavingEditor() else { return false }
        if path == selectedFilePath { return true }
        return loadFile(filePath: path)
    }

    @discardableResult
    private func loadFile(filePath: String) -> Bool {
        guard let repo = selectedRepo else { return false }
        guard let validURL = fileSystem.validatePathWithin(repoPath: repo.path, filePath: filePath) else {
            showFileError(NSError(domain: "miniOps", code: 403, userInfo: [NSLocalizedDescriptionKey: "Invalid file path within repository: \(filePath)"]))
            return false
        }
        let absolutePath = validURL.path
        do {
            let content = try fileSystem.readFile(repoPath: repo.path, filePath: absolutePath)
            self.selectedFilePath = absolutePath
            self.fileContent = content
            self.loadedFileContent = content
            self.isEditorModified = false
            saveCurrentRepoLayout()
            return true
        } catch {
            showFileError(error)
            return false
        }
    }

    @discardableResult
    public func saveCurrentFile() -> Bool {
        guard let repo = selectedRepo, let filePath = selectedFilePath else { return false }
        do {
            let current = try fileSystem.readFile(repoPath: repo.path, filePath: filePath)
            guard current == loadedFileContent else {
                throw NSError(domain: "miniOps", code: 409, userInfo: [NSLocalizedDescriptionKey:
                    "This file changed on disk. Your edits are still open; copy them before reopening the file to avoid overwriting external changes."])
            }
            try fileSystem.writeFile(repoPath: repo.path, filePath: filePath, content: fileContent)
            loadedFileContent = fileContent
            isEditorModified = false
            refreshCurrentRepoStatus()
            return true
        } catch {
            showFileError(error)
            return false
        }
    }

    public func saveCurrentRepoLayout() {
        guard let repo = selectedRepo else { return }
        var state = RepoLayoutState()
        state.selectedFilePath = selectedFilePath
        state.expandedFolderPaths = expandedFolderPaths
        state.terminalHeightRatio = terminalRatio
        state.isEditorCollapsed = isEditorCollapsed
        state.isTerminalCollapsed = isTerminalCollapsed
        state.isGitInspectorOpen = isGitInspectorOpen
        state.selectedFilesForCommit = selectedFilesForCommit
        stateStore.saveRepoState(repoPath: repo.path, state: state)
    }

    public func saveWorkbenchLayout() {
        stateStore.saveWorkbenchLayout(workbenchLayout, workspacePath: workspacePath)
    }

    public func showPanel(_ panel: WorkbenchPanel) {
        if workbenchLayout.panels(in: .left).contains(panel) {
            workbenchLayout.activeLeftTab = panel
            workbenchLayout.isLeftDockCollapsed = false
        } else {
            workbenchLayout.activeRightTab = panel
            workbenchLayout.isRightDockCollapsed = false
        }
    }

    public func toggleLeftDock() {
        workbenchLayout.isLeftDockCollapsed.toggle()
        saveWorkbenchLayout()
    }

    public func toggleRightDock() {
        workbenchLayout.isRightDockCollapsed.toggle()
        isGitInspectorOpen = !workbenchLayout.isRightDockCollapsed
        saveWorkbenchLayout()
    }

    public func toggleBottomDock() {
        workbenchLayout.isBottomDockCollapsed.toggle()
        isTerminalCollapsed = workbenchLayout.isBottomDockCollapsed
        saveWorkbenchLayout()
    }

    public func selectCenterTab(_ tab: CenterTab) {
        workbenchLayout.activeCenterTab = tab
        saveWorkbenchLayout()
    }

    public func resetWorkbenchLayout() {
        workbenchLayout = WorkbenchLayoutState()
        saveWorkbenchLayout()
    }

    public func refreshCurrentRepoStatus() {
        guard let repo = selectedRepo else { return }
        DispatchQueue.global(qos: .userInitiated).async { [gitService] in
            let (branch, isDirty, ahead, behind, changes) = gitService.getRepoStatus(repoPath: repo.path)
            let updated = RepoInfo(name: repo.name, path: repo.path, groupName: repo.groupName,
                                   branch: branch, isDirty: isDirty, ahead: ahead, behind: behind, changedFiles: changes)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.selectedRepo?.path == repo.path {
                    self.selectedRepo = updated
                    let changedPaths = Set(changes.map { $0.path })
                    self.selectedFilesForCommit = self.selectedFilesForCommit.intersection(changedPaths)
                    if let active = self.activeDiffFile, !changedPaths.contains(active) {
                        self.activeDiffFile = changes.first?.path
                    } else if self.activeDiffFile == nil {
                        self.activeDiffFile = changes.first?.path
                    }
                    self.saveCurrentRepoLayout()
                }
                if let idx = self.repositories.firstIndex(where: { $0.path == repo.path }) {
                    self.repositories[idx] = updated
                }
            }
        }
    }

    public func chooseWorkspaceDirectory() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.message = "Choose Workspace Directory"
        openPanel.prompt = "Select"

        if openPanel.runModal() == .OK, let url = openPanel.url {
            setWorkspace(path: url.path)
        }
    }

    public func refreshGraph() {
        self.graphData = GraphifyScanner.shared.loadGraph(for: selectedRepo?.path, workspacePath: workspacePath)
    }

    public func refreshTickets() {
        self.tickets = TicketScanner.shared.scanTickets(workspacePath: workspacePath, repoPath: selectedRepo?.path)
    }

    public func syncJiraTickets() {
        let settings = stateStore.getIntegrationSettings()
        guard !settings.jiraBaseURL.isEmpty, !settings.jiraEmail.isEmpty else {
            self.refreshTickets()
            return
        }
        guard CredentialStore.shared.hasSecret(for: .jira) else {
            self.refreshTickets()
            return
        }

        isSyncingTickets = true
        ticketSyncStatus = "Syncing Jira tickets…"

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let res = await JiraService.shared.syncTickets(workspacePath: self.workspacePath)
            self.isSyncingTickets = false
            if res.success {
                self.ticketSyncStatus = res.ticketCount == 1 ? "Synced 1 ticket" : "Synced \(res.ticketCount) tickets"
            } else {
                self.ticketSyncStatus = res.error ?? "Jira sync failed"
            }
            self.refreshTickets()

            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.ticketSyncStatus = nil
            }
        }
    }

    public func refreshAgents() {
        let repos = repositories
        DispatchQueue.global(qos: .utility).async { [agentScanner] in
            let agents = agentScanner.scanAgents(repositories: repos)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.activeAgents = agents
                for agent in agents where agent.isWaitingForInput {
                    if !self.previouslyNotifiedWaitingPIDs.contains(agent.pid) {
                        NotificationService.shared.sendNotification(
                            title: "\(agent.tool) May Need Attention",
                            body: "Appears idle in \(agent.repoName ?? "terminal")")
                    }
                }
                self.previouslyNotifiedWaitingPIDs = Set(agents.filter { $0.isWaitingForInput }.map { $0.pid })
            }
        }
    }

    public func setupNotificationListeners() {
        NotificationCenter.default.addObserver(forName: .miniOpsOpenWorkspace, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.chooseWorkspaceDirectory()
            }
        }
        NotificationCenter.default.addObserver(forName: .miniOpsSaveFile, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveCurrentFile()
            }
        }
        NotificationCenter.default.addObserver(forName: .miniOpsToggleGitInspector, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.showPanel(.changes)
            }
        }
        NotificationCenter.default.addObserver(forName: .miniOpsRefreshGitStatus, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshCurrentRepoStatus()
            }
        }
        NotificationCenter.default.addObserver(forName: .miniOpsToggleTerminal, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isTerminalCollapsed.toggle()
                self?.saveCurrentRepoLayout()
            }
        }
        NotificationCenter.default.addObserver(forName: .miniOpsToggleEditor, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isEditorCollapsed.toggle()
                self?.saveCurrentRepoLayout()
            }
        }
        NotificationCenter.default.addObserver(forName: .miniOpsCloneRepo, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isShowingCloneSheet = true
            }
        }
        NotificationCenter.default.addObserver(forName: .miniOpsOpenSettings, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isShowingSettingsSheet = true
            }
        }
    }

    public func handleRepoCloned(targetPath: String) {
        refreshRepositories()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self else { return }
            if let repo = self.repositories.first(where: { $0.path == targetPath }) {
                self.selectRepo(repo)
            }
        }
    }

    public func hideRepo(_ repo: RepoInfo) {
        stateStore.hideRepo(path: repo.path)
        hiddenRepoPaths.insert(repo.path)
        repositories.removeAll(where: { $0.path == repo.path })
        if selectedRepo?.path == repo.path {
            if let next = repositories.first {
                performSelectRepo(next)
            } else {
                selectedRepo = nil
                selectedFilePath = nil
                fileContent = ""
                fileTree = nil
            }
        }
        refreshAgents()
    }

    public func addRepoToHerdr(_ repo: RepoInfo) {
        let repoPath = repo.path
        let repoName = repo.name
        DispatchQueue.global(qos: .userInitiated).async {
            let result = HerdrService.shared.createWorkspace(repoPath: repoPath, label: repoName)
            guard !result.success else { return }
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Could Not Create Herdr Workspace"
                alert.informativeText = result.message
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    /// Opens a ticket's local markdown file in the editor, or launches the ticket URL in the browser.
    public func openTicket(_ ticket: TicketInfo) {
        if let localPath = ticket.localPath, localPath.lowercased().hasSuffix(".md") {
            guard let repo = selectedRepo else {
                presentAlert(title: "No Repository Selected", message: "Select a repository before opening a ticket file.")
                return
            }
            guard let relativePath = TicketScanner.shared.repoRelativePath(forTicketPath: localPath, repoPath: repo.path) else {
                presentAlert(
                    title: "Ticket Outside Repository",
                    message: "\(ticket.key) is stored outside \(repo.name) and cannot be opened here."
                )
                return
            }
            selectFile(relativePath)
            return
        }

        // Open in Jira browser if URL or key is available
        let settings = stateStore.getIntegrationSettings()
        let cleanBase = JiraService.shared.normalizeBaseURL(settings.jiraBaseURL)
        if !cleanBase.isEmpty, let url = URL(string: "\(cleanBase)/browse/\(ticket.key)") {
            NSWorkspace.shared.open(url)
            return
        }

        presentAlert(title: "No Local File", message: "\(ticket.key) has no local markdown file to open.")
    }

    public func createBranchForTicket(_ ticket: TicketInfo) {
        guard let repo = selectedRepo else {
            presentAlert(title: "No Repository Selected", message: "Select a repository before creating a feature branch.")
            return
        }

        let branchName = TicketScanner.shared.makeFeatureBranchName(ticket: ticket)
        let repoPath = repo.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = GitService.shared.createBranch(repoPath: repoPath, branchName: branchName)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if result.success {
                    self.refreshCurrentRepoStatus()
                } else {
                    self.presentAlert(
                        title: "Could Not Create Branch",
                        message: result.error ?? "Failed to create \(branchName)."
                    )
                }
            }
        }
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    public func unhideRepo(path: String) {
        stateStore.unhideRepo(path: path)
        hiddenRepoPaths.remove(path)
        refreshRepositories()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self else { return }
            if let repo = self.repositories.first(where: { $0.path == path }) {
                self.selectRepo(repo)
            }
        }
    }

    public func unhideAllRepos() {
        stateStore.unhideAllRepos()
        hiddenRepoPaths.removeAll()
        refreshRepositories()
    }

    @discardableResult
    public func reimportRepo(path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        let gitURL = URL(fileURLWithPath: expanded).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitURL.path, isDirectory: &isDir) else {
            return false
        }

        // Unhide if was hidden
        stateStore.unhideRepo(path: expanded)
        hiddenRepoPaths.remove(expanded)

        // If outside workspacePath root, register as custom repo
        let workspaceURL = URL(fileURLWithPath: workspacePath).standardized
        let repoURL = URL(fileURLWithPath: expanded).standardized
        if !repoURL.path.hasPrefix(workspaceURL.path) {
            stateStore.addCustomRepo(path: expanded)
        }

        refreshRepositories()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self else { return }
            if let repo = self.repositories.first(where: { $0.path == expanded }) {
                self.selectRepo(repo)
            }
        }
        return true
    }

    // MARK: - Center Diff Inspector
    public func inspectDiff(filePath: String) {
        self.activeDiffFile = filePath
        selectCenterTab(.diff)
    }

    // MARK: - Secondary Actions
    public func openInExternalEditor(path: String) {
        let targetPath = (path as NSString).isAbsolutePath ? path : (selectedRepo?.path ?? workspacePath) + "/" + path
        _ = ExternalEditor.open(path: targetPath)
    }

    public func revealInFinder(path: String) {
        let targetPath = (path as NSString).isAbsolutePath ? path : (selectedRepo?.path ?? workspacePath) + "/" + path
        NSWorkspace.shared.selectFile(targetPath, inFileViewerRootedAtPath: selectedRepo?.path ?? workspacePath)
    }

    public func copyPathToClipboard(_ path: String, relative: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if relative, let repo = selectedRepo, path.hasPrefix(repo.path) {
            let rel = String(path.dropFirst(repo.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            pasteboard.setString(rel, forType: .string)
        } else {
            pasteboard.setString(path, forType: .string)
        }
    }

    public func openRemoteInBrowser(repo: RepoInfo) {
        if let url = gitService.getRemoteWebURL(repoPath: repo.path) {
            NSWorkspace.shared.open(url)
        }
    }

    public func openTerminalForRepo(_ repo: RepoInfo) {
        selectRepo(repo)
        workbenchLayout.isBottomDockCollapsed = false
    }

    // MARK: - Repository-Scoped Commit Selection
    public func setCommitSelection(_ selection: Set<String>, for repoPath: String? = nil) {
        let targetPath = repoPath ?? selectedRepo?.path
        guard let path = targetPath else {
            self.selectedFilesForCommit = selection
            return
        }
        if selectedRepo?.path == path {
            self.selectedFilesForCommit = selection
        }
        var state = stateStore.getRepoState(repoPath: path)
        state.selectedFilesForCommit = selection
        stateStore.saveRepoState(repoPath: path, state: state)
    }

    public func toggleCommitSelection(for filePath: String, in repoPath: String? = nil) {
        let targetPath = repoPath ?? selectedRepo?.path
        guard let path = targetPath else { return }
        var current = (selectedRepo?.path == path) ? selectedFilesForCommit : (stateStore.getRepoState(repoPath: path).selectedFilesForCommit ?? [])
        if current.contains(filePath) {
            current.remove(filePath)
        } else {
            current.insert(filePath)
        }
        setCommitSelection(current, for: path)
    }

    // MARK: - Repository-Isolated Commit & Reconcile
    public func executeSelectiveCommit(
        repoPath: String,
        message: String,
        selectedPaths: [String],
        completion: @escaping (GitOperationResult) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [gitService] in
            let result = gitService.selectiveCommit(
                repoPath: repoPath,
                message: message,
                selectedPaths: selectedPaths
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if result.success {
                    // Update persisted selection for the target repository
                    var state = self.stateStore.getRepoState(repoPath: repoPath)
                    state.selectedFilesForCommit = []
                    self.stateStore.saveRepoState(repoPath: repoPath, state: state)

                    // Only modify active UI state if currently selected repo matches repoPath
                    if self.selectedRepo?.path == repoPath {
                        self.selectedFilesForCommit.removeAll()
                        self.refreshCurrentRepoStatus()
                    }
                }
                completion(result)
            }
        }
    }

    public func executeReconcile(
        repoPath: String,
        message: String,
        selectedPaths: [String],
        completion: @escaping (GitOperationResult) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [gitService] in
            let result = gitService.reconcile(
                repoPath: repoPath,
                message: message,
                selectedPaths: selectedPaths
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if result.success {
                    var state = self.stateStore.getRepoState(repoPath: repoPath)
                    state.selectedFilesForCommit = []
                    self.stateStore.saveRepoState(repoPath: repoPath, state: state)

                    if self.selectedRepo?.path == repoPath {
                        self.selectedFilesForCommit.removeAll()
                        self.refreshCurrentRepoStatus()
                    }
                } else if result.partialSuccess {
                    if self.selectedRepo?.path == repoPath {
                        self.refreshCurrentRepoStatus()
                    }
                }
                completion(result)
            }
        }
    }
}
