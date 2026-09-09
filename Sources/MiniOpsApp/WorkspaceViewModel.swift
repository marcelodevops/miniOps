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
    @Published public var selectedFilesForCommit: Set<String> = []

    // Alert for unsaved changes
    @Published public var showUnsavedChangesAlert: Bool = false
    private var pendingFileSwitchPath: String?
    private var pendingRepoSwitch: RepoInfo?

    private let scanner = WorkspaceScanner.shared
    private let gitService = GitService.shared
    private let fileSystem = FileSystemService.shared
    private let stateStore = WorkspaceStateStore.shared

    public init() {
        let appState = stateStore.getAppState()
        let initialWorkspace = appState.lastWorkspacePath ?? "~/repos"
        setWorkspace(path: initialWorkspace)

        // Restore last selected repo
        if let lastRepoPath = appState.lastSelectedRepoPath,
           let repo = repositories.first(where: { $0.path == lastRepoPath }) {
            selectRepo(repo)
        } else if let firstRepo = repositories.first {
            selectRepo(firstRepo)
        }
        setupNotificationListeners()
    }

    public func setWorkspace(path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        self.workspacePath = expanded
        stateStore.saveWorkspacePath(expanded)
        refreshRepositories()
    }

    public func refreshRepositories() {
        guard !workspacePath.isEmpty else { return }
        repositories = scanner.scan(rootPath: workspacePath)

        // If selected repo still exists, refresh it
        if selectedRepo != nil {
            if let updated = repositories.first(where: { $0.path == current.path }) {
                selectedRepo = updated
            }
        }
    }

    public func selectRepo(_ repo: RepoInfo) {
        if isEditorModified {
            pendingRepoSwitch = repo
            showUnsavedChangesAlert = true
            return
        }
        performSelectRepo(repo)
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

        // Restore file selection
        if let filePath = state.selectedFilePath,
           FileManager.default.fileExists(atPath: filePath) {
            loadFile(filePath: filePath)
        } else {
            selectedFilePath = nil
            fileContent = ""
            isEditorModified = false
        }

        // Pre-select all modified files for commit by default
        selectedFilesForCommit = Set(repo.changedFiles.map { $0.path })
    }

    public func selectFile(_ path: String) {
        if path == selectedFilePath { return }
        if isEditorModified {
            pendingFileSwitchPath = path
            showUnsavedChangesAlert = true
            return
        }
        loadFile(filePath: path)
    }

    private func loadFile(filePath: String) {
        guard let repo = selectedRepo else { return }
        do {
            let content = try fileSystem.readFile(repoPath: repo.path, filePath: filePath)
            self.selectedFilePath = filePath
            self.fileContent = content
            self.isEditorModified = false
            saveCurrentRepoLayout()
        } catch {
            print("Failed to read file \(filePath): \(error.localizedDescription)")
        }
    }

    public func saveCurrentFile() {
        guard let repo = selectedRepo, let filePath = selectedFilePath else { return }
        do {
            try fileSystem.writeFile(repoPath: repo.path, filePath: filePath, content: fileContent)
            self.isEditorModified = false
            refreshCurrentRepoStatus()
        } catch {
            print("Failed to save file \(filePath): \(error.localizedDescription)")
        }
    }

    public func discardUnsavedChangesAndProceed() {
        isEditorModified = false
        if let nextRepo = pendingRepoSwitch {
            pendingRepoSwitch = nil
            performSelectRepo(nextRepo)
        } else if let nextFile = pendingFileSwitchPath {
            pendingFileSwitchPath = nil
            loadFile(filePath: nextFile)
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
        stateStore.saveRepoState(repoPath: repo.path, state: state)
    }

    public func refreshCurrentRepoStatus() {
        guard let repo = selectedRepo else { return }
        let (branch, isDirty, ahead, behind, changes) = gitService.getRepoStatus(repoPath: repo.path)
        let updated = RepoInfo(
            name: repo.name,
            path: repo.path,
            groupName: repo.groupName,
            branch: branch,
            isDirty: isDirty,
            ahead: ahead,
            behind: behind,
            changedFiles: changes
        )
        self.selectedRepo = updated
        if let idx = repositories.firstIndex(where: { $0.path == repo.path }) {
            repositories[idx] = updated
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
                self?.isGitInspectorOpen.toggle()
                self?.saveCurrentRepoLayout()
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
    }
}
