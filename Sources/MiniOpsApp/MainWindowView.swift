import SwiftUI
import AppKit
import MiniOpsCore

public enum InspectorTab: String, CaseIterable {
    case changes = "Changes"
    case stashes = "Stashes"
    case worktrees = "Worktrees"
    case notes = "Notes"
    case agents = "Agents"
    case tickets = "Tickets"
    case graph = "Graph"
}

public struct MainWindowView: View {
    @ObservedObject public var viewModel: WorkspaceViewModel
    @State private var repositorySearch = ""
    @State private var activeInspectorTab: InspectorTab = .changes
    @State private var isShowingBatchGitSheet: Bool = false
    @State private var isPerformingGitAction: Bool = false
    @State private var gitActionBanner: String?

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationSplitView {
            // Sidebar: Repositories & File Navigator
            VStack(spacing: 0) {
                // Workspace Header
                HStack {
                    Image(systemName: "folder.badge.gearshape")
                        .foregroundColor(.secondary)
                    Text(URL(fileURLWithPath: viewModel.workspacePath).lastPathComponent)
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                    Spacer()
                    Button(action: { viewModel.isShowingCloneSheet = true }) {
                        Image(systemName: "plus.rectangle.on.folder")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Clone or Create Repository (Cmd+Shift+N)")

                    Button(action: { viewModel.chooseWorkspaceDirectory() }) {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Change Workspace Directory")

                    if viewModel.isScanning {
                        ProgressView().controlSize(.small).help("Scanning repositories…")
                    }
                    Button(action: { viewModel.refreshRepositories() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Rescan Repositories")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Repositories List
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("REPOSITORIES (\(viewModel.repositories.count))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: { isShowingBatchGitSheet = true }) {
                            Text("Batch Git")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.borderless)
                        .help("Run Batch Git Actions Across Repositories")
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 2)

                    TextField("Find a repository…", text: $repositorySearch)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    RepoListView(
                        repos: viewModel.repositories.filter {
                            repositorySearch.isEmpty || $0.name.localizedCaseInsensitiveContains(repositorySearch)
                                || ($0.groupName?.localizedCaseInsensitiveContains(repositorySearch) ?? false)
                        },
                        selectedRepoPath: viewModel.selectedRepo?.path,
                        onSelectRepo: { repo in
                            viewModel.selectRepo(repo)
                        }
                    )
                }
                .frame(minHeight: 180, idealHeight: 280, maxHeight: 320)

                Divider()

                // File Navigator for Selected Repo
                if let repo = viewModel.selectedRepo, let rootNode = viewModel.fileTree {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("FILES — \(repo.name)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                        .padding(.bottom, 2)

                        FileNavigatorView(
                            repoPath: repo.path,
                            rootNode: rootNode,
                            selectedFilePath: viewModel.selectedFilePath,
                            expandedFolderPaths: $viewModel.expandedFolderPaths,
                            onSelectFile: { filePath in
                                viewModel.selectFile(filePath)
                            }
                        )
                    }
                } else {
                    VStack {
                        Spacer()
                        Text("Select a repository")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 350)
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 350)
        } detail: {
            // Main Stage
            if let repo = viewModel.selectedRepo {
                VStack(spacing: 0) {
                    // Top App Toolbar
                    topToolbar(repo: repo)

                    // Optional Git Banner
                    if let banner = gitActionBanner {
                        HStack {
                            Image(systemName: "info.circle")
                            Text(banner)
                                .font(.system(size: 11))
                            Spacer()
                            Button(action: { gitActionBanner = nil }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12))
                        Divider()
                    }

                    Divider()

                    // Main Content: Canvas or Inspector Panel
                    if viewModel.isGitInspectorOpen {
                        VStack(spacing: 0) {
                            // Inspector tab header
                            HStack(spacing: 8) {
                                Picker("", selection: $activeInspectorTab) {
                                    Text("Changes (\(repo.changedFiles.count))").tag(InspectorTab.changes)
                                    Text("Stashes").tag(InspectorTab.stashes)
                                    Text("Worktrees").tag(InspectorTab.worktrees)
                                    Text("Notes").tag(InspectorTab.notes)
                                    Text("Agents (\(viewModel.activeAgents.count))").tag(InspectorTab.agents)
                                    Text("Tickets (\(viewModel.tickets.count))").tag(InspectorTab.tickets)
                                    Text("Graph").tag(InspectorTab.graph)
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 420)

                                Spacer()

                                Button(action: {
                                    withAnimation {
                                        viewModel.isGitInspectorOpen = false
                                        viewModel.saveCurrentRepoLayout()
                                    }
                                }) {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(NSColor.controlBackgroundColor))

                            Divider()

                            switch activeInspectorTab {
                            case .changes:
                                GitChangesView(
                                    repoPath: repo.path,
                                    changes: repo.changedFiles,
                                    selectedFilesForCommit: $viewModel.selectedFilesForCommit,
                                    onGitOperationDone: {
                                        viewModel.refreshCurrentRepoStatus()
                                    }
                                )
                            case .stashes:
                                StashManagerView(
                                    repoPath: repo.path,
                                    onStashChanged: {
                                        viewModel.refreshCurrentRepoStatus()
                                    }
                                )
                            case .worktrees:
                                WorktreeManagerView(
                                    repoPath: repo.path,
                                    onWorktreeChanged: {
                                        viewModel.refreshCurrentRepoStatus()
                                    }
                                )
                            case .notes:
                                RepoNotesView(repoPath: repo.path)
                            case .agents:
                                AgentInspectorView(
                                    agents: viewModel.activeAgents,
                                    onSelectRepo: { path in
                                        if let target = viewModel.repositories.first(where: { $0.path == path }) {
                                            viewModel.selectRepo(target)
                                        }
                                    },
                                    onRefresh: {
                                        viewModel.refreshAgents()
                                    }
                                )
                            case .tickets:
                                TicketManagerView(
                                    repoPath: repo.path,
                                    tickets: viewModel.tickets,
                                    onBranchCreated: {
                                        viewModel.refreshCurrentRepoStatus()
                                    },
                                    onRefresh: {
                                        viewModel.refreshTickets()
                                    }
                                )
                            case .graph:
                                GraphifyVisualizerView(
                                    graphData: viewModel.graphData,
                                    onSelectFile: { filePath in
                                        viewModel.selectFile(filePath)
                                    },
                                    onRefresh: {
                                        viewModel.refreshGraph()
                                    }
                                )
                            }
                        }
                    } else {
                        SplitWorkspaceCanvasView(
                            repoPath: repo.path,
                            terminalRatio: $viewModel.terminalRatio,
                            isEditorCollapsed: $viewModel.isEditorCollapsed,
                            isTerminalCollapsed: $viewModel.isTerminalCollapsed,
                            editorContent: {
                                if let selectedFile = viewModel.selectedFilePath {
                                    EditorContainerView(
                                        text: $viewModel.fileContent,
                                        isModified: $viewModel.isEditorModified,
                                        filePath: selectedFile,
                                        onSave: {
                                            viewModel.saveCurrentFile()
                                        }
                                    )
                                } else {
                                    VStack(spacing: 12) {
                                        Spacer()
                                        Image(systemName: "doc.text.magnifyingglass")
                                            .font(.system(size: 36))
                                            .foregroundColor(.secondary.opacity(0.6))
                                        Text("Select a file from the sidebar to view and edit")
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color(NSColor.textBackgroundColor))
                                }
                            },
                            onLayoutChange: {
                                viewModel.saveCurrentRepoLayout()
                            }
                        )
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor.opacity(0.8))
                    Text("No Repository Selected")
                        .font(.title3.bold())
                    Text("Choose a repository from the sidebar to start working.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $isShowingBatchGitSheet) {
            BatchGitSheetView(repos: viewModel.repositories, onComplete: {
                viewModel.refreshRepositories()
            })
        }
        .sheet(isPresented: $viewModel.isShowingCloneSheet) {
            CloneRepoSheetView(
                workspacePath: viewModel.workspacePath,
                onRepoCloned: { targetPath in
                    viewModel.isShowingCloneSheet = false
                    viewModel.handleRepoCloned(targetPath: targetPath)
                },
                onDismiss: {
                    viewModel.isShowingCloneSheet = false
                }
            )
        }
    }

    private func topToolbar(repo: RepoInfo) -> some View {
        HStack(spacing: 10) {
            // Repo info & branch switcher
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)
                Text(repo.name)
                    .font(.system(size: 13, weight: .bold))

                BranchSwitcherView(
                    repoPath: repo.path,
                    currentBranch: repo.branch,
                    onBranchChanged: {
                        viewModel.refreshCurrentRepoStatus()
                    }
                )

                if repo.isDirty {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                }

                if repo.ahead > 0 || repo.behind > 0 {
                    HStack(spacing: 2) {
                        if repo.ahead > 0 { Text("↑\(repo.ahead)").foregroundColor(.green) }
                        if repo.behind > 0 { Text("↓\(repo.behind)").foregroundColor(.blue) }
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
            }

            Spacer()

            // Quick Git Actions: Fetch & Pull
            HStack(spacing: 4) {
                Button(action: executeFetch) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Fetch")
                    }
                    .font(.system(size: 11))
                }
                .disabled(isPerformingGitAction)
                .help("Fetch all remotes and prune")

                Button(action: executePull) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle")
                        Text("Pull")
                    }
                    .font(.system(size: 11))
                }
                .disabled(isPerformingGitAction)
                .help("Pull current branch (--ff-only)")
            }

            Divider().frame(height: 16)

            // View toggles
            HStack(spacing: 8) {
                // Git Inspector toggle
                Button(action: {
                    withAnimation {
                        viewModel.isGitInspectorOpen.toggle()
                        viewModel.saveCurrentRepoLayout()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "sidebar.right")
                        Text("Tools (\(repo.changedFiles.count))")
                    }
                    .font(.system(size: 11, weight: viewModel.isGitInspectorOpen ? .bold : .regular))
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isGitInspectorOpen ? .accentColor : .secondary.opacity(0.2))

                // Toggle Editor
                Button(action: {
                    withAnimation {
                        viewModel.isEditorCollapsed.toggle()
                        viewModel.saveCurrentRepoLayout()
                    }
                }) {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.borderless)
                .foregroundColor(viewModel.isEditorCollapsed ? .secondary : .accentColor)
                .help("Toggle Editor (Cmd+E)")

                // Toggle Terminal
                Button(action: {
                    withAnimation {
                        viewModel.isTerminalCollapsed.toggle()
                        viewModel.saveCurrentRepoLayout()
                    }
                }) {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.borderless)
                .foregroundColor(viewModel.isTerminalCollapsed ? .secondary : .accentColor)
                .help("Toggle Terminal (Cmd+J)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func executeFetch() {
        guard let repo = viewModel.selectedRepo else { return }
        isPerformingGitAction = true
        gitActionBanner = "Fetching remotes for \(repo.name)..."

        DispatchQueue.global(qos: .userInitiated).async {
            let res = GitService.shared.fetch(repoPath: repo.path)
            DispatchQueue.main.async {
                isPerformingGitAction = false
                gitActionBanner = res.success ? "Fetch completed." : (res.error ?? "Fetch failed.")
                viewModel.refreshCurrentRepoStatus()
            }
        }
    }

    private func executePull() {
        guard let repo = viewModel.selectedRepo else { return }
        isPerformingGitAction = true
        gitActionBanner = "Pulling latest changes for \(repo.name)..."

        DispatchQueue.global(qos: .userInitiated).async {
            let res = GitService.shared.pull(repoPath: repo.path)
            DispatchQueue.main.async {
                isPerformingGitAction = false
                gitActionBanner = res.success ? (res.output.isEmpty ? "Pulled successfully." : res.output) : (res.error ?? "Pull failed.")
                viewModel.refreshCurrentRepoStatus()
            }
        }
    }
}
