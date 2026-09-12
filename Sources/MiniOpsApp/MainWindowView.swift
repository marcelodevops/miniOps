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
    @State private var isShowingBatchGitSheet: Bool = false
    @State private var isPerformingGitAction: Bool = false
    @State private var gitActionBanner: String?
    @State private var isShowingCommitPushPrompt: Bool = false
    @State private var commitPushMessage: String = ""
    @State private var isTicketNavigatorExpanded: Bool = true
    @State private var leftDragStart: Double?
    @State private var rightDragStart: Double?
    @State private var bottomDragStart: Double?
    @State private var isDraggingLeftDivider: Bool = false
    @State private var isDraggingRightDivider: Bool = false
    @State private var isDraggingBottomDivider: Bool = false

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Unified Workbench Header Toolbar
            topWorkbenchToolbar

            // 2. Optional Git Action Banner
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

            // 3. Four-Zone Workbench Body
            GeometryReader { geo in
                let widths = WorkbenchDockGeometry.resolve(
                    width: geo.size.width,
                    left: viewModel.workbenchLayout.isLeftDockCollapsed ? 0 : viewModel.workbenchLayout.leftDockWidth,
                    right: viewModel.workbenchLayout.isRightDockCollapsed ? 0 : viewModel.workbenchLayout.rightDockWidth
                )
                HStack(spacing: 0) {
                    // LEFT DOCK: Repositories & Tickets
                    if !viewModel.workbenchLayout.isLeftDockCollapsed {
                        leftDockView
                            .frame(width: widths.left)

                        // Draggable Left Divider
                        leftDividerBar(width: widths.left, maximum: geo.size.width - widths.right - 368)
                    }

                    // CENTER STAGE & BOTTOM TERMINAL DOCK
                    VStack(spacing: 0) {
                        // Center Document / View Stage
                        centerStageView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // BOTTOM DOCK: Embedded Terminal
                        if !viewModel.workbenchLayout.isBottomDockCollapsed {
                            bottomDividerBar(containerHeight: geo.size.height)

                            let termHeight = max(geo.size.height * CGFloat(viewModel.workbenchLayout.bottomDockHeightRatio), 110)
                            bottomDockView
                                .frame(height: termHeight)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // RIGHT DOCK: Context Tools (Changes, Agents, Stashes, Worktrees, Notes)
                    if !viewModel.workbenchLayout.isRightDockCollapsed {
                        rightDividerBar(width: widths.right, maximum: geo.size.width - widths.left - 368)

                        rightDockView
                            .frame(width: widths.right)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .coordinateSpace(name: "workbench")
            }

            // 4. Workbench Status Bar
            WorkbenchStatusBarView(viewModel: viewModel)
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
        .sheet(isPresented: $viewModel.isShowingSettingsSheet) {
            SettingsSheetContainer(
                viewModel: viewModel,
                isPresented: $viewModel.isShowingSettingsSheet
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .miniOpsFetch)) { _ in
            executeFetch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .miniOpsPull)) { _ in
            executePull()
        }
        .onReceive(NotificationCenter.default.publisher(for: .miniOpsPush)) { _ in
            executePush()
        }
        .onReceive(NotificationCenter.default.publisher(for: .miniOpsAddCommitPush)) { _ in
            promptForCommitAndPush()
        }
        .alert("Commit & Push", isPresented: $isShowingCommitPushPrompt) {
            TextField("Commit message", text: $commitPushMessage)
            Button("Cancel", role: .cancel) { }
            Button("Commit & Push") { executeAddCommitPush() }
                .disabled(commitPushMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Stages every change in \(viewModel.selectedRepo?.name ?? "the repository"), commits it with this message and pushes the current branch.")
        }
    }

    // MARK: - Top Workbench Toolbar
    private var topWorkbenchToolbar: some View {
        HStack(spacing: 12) {
            // Left: Toggle Left Dock & Center Tabs
            HStack(spacing: 8) {
                Button(action: { viewModel.toggleLeftDock() }) {
                    Image(systemName: viewModel.workbenchLayout.isLeftDockCollapsed ? "sidebar.left" : "sidebar.leading")
                        .font(.system(size: 11))
                        .foregroundColor(viewModel.workbenchLayout.isLeftDockCollapsed ? .secondary : .accentColor)
                }
                .buttonStyle(.borderless)
                .help("Toggle Sidebar (Cmd+1)")

                Picker("", selection: Binding(
                    get: { viewModel.workbenchLayout.activeCenterTab },
                    set: { viewModel.selectCenterTab($0) }
                )) {
                    ForEach(CenterTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
            }

            Spacer()

            // Center / Right: Git Actions for selected repo
            if let repo = viewModel.selectedRepo {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.accentColor)
                    Text(repo.name)
                        .font(.system(size: 12, weight: .bold))

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
                            .frame(width: 7, height: 7)
                    }

                    if repo.ahead > 0 || repo.behind > 0 {
                        HStack(spacing: 2) {
                            if repo.ahead > 0 { Text("↑\(repo.ahead)").foregroundColor(.green) }
                            if repo.behind > 0 { Text("↓\(repo.behind)").foregroundColor(.blue) }
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }

                    Divider().frame(height: 14)

                    // Quick Git Actions: Fetch, Pull, Push, Commit & Push
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

                        Button(action: executePush) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.circle")
                                Text("Push")
                            }
                            .font(.system(size: 11))
                        }
                        .disabled(isPerformingGitAction)
                        .help("Push current branch to remote")

                        Button(action: promptForCommitAndPush) {
                            HStack(spacing: 3) {
                                Image(systemName: "bolt.horizontal.circle")
                                Text("Commit & Push")
                            }
                            .font(.system(size: 11))
                        }
                        .disabled(isPerformingGitAction || !repo.isDirty)
                        .help("Stage all changes, commit and push (xgit)")
                    }
                }
            } else {
                Text(URL(fileURLWithPath: viewModel.workspacePath).lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Far Right: Dock Toggles
            HStack(spacing: 6) {
                Button(action: { viewModel.toggleBottomDock() }) {
                    Image(systemName: "terminal")
                        .font(.system(size: 11))
                        .foregroundColor(viewModel.workbenchLayout.isBottomDockCollapsed ? .secondary : .accentColor)
                }
                .buttonStyle(.borderless)
                .help("Toggle Terminal (Cmd+J)")

                Button(action: { viewModel.toggleRightDock() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "sidebar.right")
                        if let repo = viewModel.selectedRepo, repo.changedFiles.count > 0 {
                            Text("Tools (\(repo.changedFiles.count))")
                        } else {
                            Text("Tools")
                        }
                    }
                    .font(.system(size: 11, weight: viewModel.workbenchLayout.isRightDockCollapsed ? .regular : .bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.workbenchLayout.isRightDockCollapsed ? .secondary.opacity(0.2) : .accentColor)
                .help("Toggle Tools Panel (Cmd+3)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Left Dock View
    private var leftDockView: some View {
        VStack(spacing: 0) {
            // Left Dock Header
            HStack(spacing: 6) {
                Picker("", selection: $viewModel.workbenchLayout.activeLeftTab) {
                    ForEach(viewModel.workbenchLayout.panels(in: .left), id: \.self) { panel in
                        Text(panelTitle(panel)).tag(panel)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                movePanelMenu(viewModel.workbenchLayout.activeLeftTab, from: .left)

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

                Button(action: { viewModel.refreshRepositories() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Rescan Repositories")

                Button(action: { viewModel.isShowingSettingsSheet = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Settings (Cmd+,)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content according to activeLeftTab
            if viewModel.workbenchLayout.panels(in: .left).isEmpty {
                Text("Move a panel here from the right dock.").foregroundColor(.secondary).padding()
                Spacer()
            } else {
                panelContent(viewModel.workbenchLayout.activeLeftTab)
            }

        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }

    @ViewBuilder
    private func panelContent(_ panel: WorkbenchPanel) -> some View {
        switch panel {
            case .repos:
                let visibleRepositories = viewModel.visibleRepositories(for: viewModel.repositoryPanelFilter, search: repositorySearch)

                VStack(spacing: 0) {
                    HStack {
                        Text("REPOSITORIES (\(visibleRepositories.count))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Toggle(
                            "Dirty",
                            isOn: Binding(
                                get: { viewModel.repositoryPanelFilter == .dirty },
                                set: { viewModel.repositoryPanelFilter = $0 ? .dirty : .all }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10))
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

                    if case .tag(let t) = viewModel.repositoryPanelFilter {
                        HStack(spacing: 4) {
                            Text("Type: \(t)")
                                .font(.system(size: 10, weight: .semibold))
                            Button(action: { viewModel.repositoryPanelFilter = .all }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                    } else if case .origin(let o) = viewModel.repositoryPanelFilter {
                        HStack(spacing: 4) {
                            Text("Origin: \(o)")
                                .font(.system(size: 10, weight: .semibold))
                            Button(action: { viewModel.repositoryPanelFilter = .all }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                    }

                    TextField("Find a repository…", text: $repositorySearch)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)

                    RepoListView(
                        repos: visibleRepositories,
                        selectedRepoPath: viewModel.selectedRepo?.path,
                        fileTree: viewModel.fileTree,
                        selectedFilePath: viewModel.selectedFilePath,
                        expandedFolderPaths: $viewModel.expandedFolderPaths,
                        onSelectRepo: { repo in
                            viewModel.selectRepo(repo)
                        },
                        onSelectFile: { filePath in
                            viewModel.selectFile(filePath)
                        },
                        onHideRepo: { repo in
                            viewModel.hideRepo(repo)
                        },
                        onAddToHerdr: { repo in
                            viewModel.addRepoToHerdr(repo)
                        },
                        onOpenTerminal: { repo in
                            viewModel.openTerminalForRepo(repo)
                        },
                        onOpenInExternalEditor: { repo in
                            viewModel.openInExternalEditor(path: repo.path)
                        },
                        onOpenRemote: { repo in
                            viewModel.openRemoteInBrowser(repo: repo)
                        }
                    )
                    .frame(maxHeight: .infinity)
                }

            case .tickets:
                let filteredTickets = viewModel.filteredTickets(for: viewModel.ticketPanelFilter)

                VStack(spacing: 0) {
                    if case .category(let c) = viewModel.ticketPanelFilter {
                        HStack(spacing: 4) {
                            Text("State: \(c)")
                                .font(.system(size: 10, weight: .semibold))
                            Button(action: { viewModel.ticketPanelFilter = .all }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                    } else if case .priority(let p) = viewModel.ticketPanelFilter {
                        HStack(spacing: 4) {
                            Text("Priority: \(p)")
                                .font(.system(size: 10, weight: .semibold))
                            Button(action: { viewModel.ticketPanelFilter = .all }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                    }

                    TicketNavigatorView(
                        tickets: filteredTickets,
                        selectedRepoPath: viewModel.selectedRepo?.path,
                        isExpanded: $isTicketNavigatorExpanded,
                        openOnly: Binding(
                            get: { viewModel.ticketPanelFilter == .open },
                            set: { viewModel.ticketPanelFilter = $0 ? .open : .all }
                        ),
                        isSyncing: viewModel.isSyncingTickets,
                        syncStatus: viewModel.ticketSyncStatus,
                        onSelectTicket: { ticket in
                            viewModel.selectTicket(ticket)
                        },
                        onCreateBranch: { ticket in
                            viewModel.createBranchForTicket(ticket)
                        },
                        onRefresh: {
                            viewModel.syncJiraTickets()
                        }
                    )
                    .frame(maxHeight: .infinity)
                }
            case .changes:
                if let repo = viewModel.selectedRepo {
                    GitChangesView(
                        repoPath: repo.path,
                        changes: repo.changedFiles,
                        statusRevision: viewModel.statusRevision,
                        selectedFilesForCommit: $viewModel.selectedFilesForCommit,
                        onGitOperationDone: {
                            viewModel.refreshCurrentRepoStatus()
                        },
                        onOpenStashes: {
                            viewModel.showPanel(.stashes)
                        },
                        onOpenWorktrees: {
                            viewModel.showPanel(.worktrees)
                        },
                        onOpenBatchGit: {
                            isShowingBatchGitSheet = true
                        },
                        onInspectDiffInCenter: { file in
                            viewModel.inspectDiff(filePath: file)
                        },
                        onExecuteCommit: { repoPath, message, selected, completion in
                            viewModel.executeSelectiveCommit(repoPath: repoPath, message: message, selectedPaths: selected, completion: completion)
                        },
                        onExecuteReconcile: { repoPath, message, selected, completion in
                            viewModel.executeReconcile(repoPath: repoPath, message: message, selectedPaths: selected, completion: completion)
                        },
                        currentRepoPath: {
                            viewModel.selectedRepo?.path
                        },
                        onDiffLoaded: { _, diff in
                            viewModel.sideDiffContent = diff
                        }
                    )
                    .id(repo.path)
                } else {
                    noRepoPlaceholder(for: "Git Changes")
                }

            case .agents:
                AgentInspectorView(
                    agents: viewModel.activeAgents,
                    waitingOnly: Binding(
                        get: { viewModel.agentPanelFilter == .waiting },
                        set: { viewModel.agentPanelFilter = $0 ? .waiting : .all }
                    ),
                    onSelectRepo: { path in
                        if let target = viewModel.repositories.first(where: { $0.path == path }) {
                            viewModel.selectRepo(target)
                        }
                    },
                    onRefresh: {
                        viewModel.refreshAgents()
                    },
                    onSelectAgent: { agent in
                        viewModel.selectAgent(agent)
                    }
                )

            case .stashes:
                if let repo = viewModel.selectedRepo {
                    StashManagerView(
                        repoPath: repo.path,
                        onStashChanged: {
                            viewModel.refreshCurrentRepoStatus()
                        }
                    )
                } else {
                    noRepoPlaceholder(for: "Git Stashes")
                }

            case .worktrees:
                if let repo = viewModel.selectedRepo {
                    WorktreeManagerView(
                        repoPath: repo.path,
                        onWorktreeChanged: {
                            viewModel.refreshCurrentRepoStatus()
                        }
                    )
                } else {
                    noRepoPlaceholder(for: "Git Worktrees")
                }

            case .notes:
                if let repo = viewModel.selectedRepo {
                    RepoNotesView(repoPath: repo.path)
                } else {
                    noRepoPlaceholder(for: "Repository Notes")
                }
        }
    }

    private func panelTitle(_ panel: WorkbenchPanel) -> String {
        switch panel {
        case .repos: return "Repos (\(viewModel.repositories.count))"
        case .tickets: return "Tickets (\(viewModel.tickets.count))"
        case .agents: return "Agents (\(viewModel.activeAgents.count))"
        case .changes: return "Changes (\(viewModel.selectedRepo?.changedFiles.count ?? 0))"
        default: return panel.rawValue
        }
    }

    private func movePanelMenu(_ panel: WorkbenchPanel, from dock: SideDock) -> some View {
        Menu {
            Button(dock == .left ? "Move to Right Dock" : "Move to Left Dock") {
                viewModel.workbenchLayout.move(panel, to: dock == .left ? .right : .left)
            }
        } label: {
            Image(systemName: "arrow.left.arrow.right")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Move Panel")
        .disabled(viewModel.workbenchLayout.panels(in: dock).isEmpty)
    }

    // MARK: - Center Stage View
    @ViewBuilder
    private var centerStageView: some View {
        switch viewModel.workbenchLayout.activeCenterTab {
        case .editor:
            editorStageContent
        case .diff:
            CenterDiffStageView(viewModel: viewModel)
        case .ticket:
            TicketDetailStageView(viewModel: viewModel)
        case .agent:
            AgentDetailStageView(viewModel: viewModel)
        case .overview:
            OverviewDashboardView(viewModel: viewModel)
        case .focus:
            FocusWorkView(viewModel: viewModel)
        case .graph:
            GraphifyVisualizerView(
                graphData: viewModel.graphData,
                onSelectFile: { filePath in
                    viewModel.selectFile(filePath)
                    viewModel.selectCenterTab(.editor)
                },
                onRefresh: {
                    viewModel.refreshGraph()
                }
            )
        }
    }

    @ViewBuilder
    private var editorStageContent: some View {
        if let selectedFile = viewModel.selectedFilePath {
            EditorContainerView(
                text: $viewModel.fileContent,
                isModified: $viewModel.isEditorModified,
                filePath: selectedFile,
                onSave: {
                    viewModel.saveCurrentFile()
                }
            )
        } else if let repo = viewModel.selectedRepo {
            // Selected repo welcome card
            VStack(spacing: 14) {
                Spacer()
                Image(systemName: "folder.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                Text(repo.name)
                    .font(.title2.bold())
                Text("Branch: \(repo.branch) • \(repo.changedFiles.count) modified files")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    Button("View Changes") {
                        viewModel.showPanel(.changes)
                    }
                    .buttonStyle(.bordered)

                    Button("Open Terminal") {
                        viewModel.workbenchLayout.isBottomDockCollapsed = false
                    }
                    .buttonStyle(.bordered)

                    Button("View Overview") {
                        viewModel.selectCenterTab(.overview)
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
        } else {
            VStack(spacing: 14) {
                Spacer()
                Image(systemName: "macwindow")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor.opacity(0.7))
                Text("miniOps Native Workbench")
                    .font(.title2.bold())
                Text("Select a repository from the left dock, or browse workspace tools.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    Button("Open Workspace Overview") {
                        viewModel.selectCenterTab(.overview)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Browse Tickets") {
                        viewModel.showPanel(.tickets)
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    // MARK: - Right Dock View
    private var rightDockView: some View {
        VStack(spacing: 0) {
            // Header with tab selector and collapse button
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    Picker("", selection: $viewModel.workbenchLayout.activeRightTab) {
                        ForEach(viewModel.workbenchLayout.panels(in: .right), id: \.self) { panel in
                            Text(panelTitle(panel)).tag(panel)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                movePanelMenu(viewModel.workbenchLayout.activeRightTab, from: .right)

                Spacer()

                Button(action: {
                    withAnimation {
                        viewModel.toggleRightDock()
                    }
                }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Close Tools Panel (Cmd+3)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content according to activeRightTab
            if viewModel.workbenchLayout.panels(in: .right).isEmpty {
                Text("Move a panel here from the left dock.").foregroundColor(.secondary).padding()
                Spacer()
            } else {
                panelContent(viewModel.workbenchLayout.activeRightTab)
            }

        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }

    private func noRepoPlaceholder(for feature: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.6))
            Text("\(feature) requires a repository")
                .font(.system(size: 12, weight: .semibold))
            Text("Select a repository from the left dock to inspect \(feature.lowercased()).")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom Dock View (Terminal)
    private var bottomDockView: some View {
        VStack(spacing: 0) {
            // Terminal Header
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 11))
                Text("Terminal")
                    .font(.system(size: 11, weight: .semibold))

                let pathLabel = viewModel.selectedRepo?.name ?? URL(fileURLWithPath: viewModel.workspacePath).lastPathComponent
                Text("(\(pathLabel) • /bin/zsh -l)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    withAnimation {
                        viewModel.toggleBottomDock()
                    }
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("Hide Terminal (Cmd+J)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(Divider(), alignment: .top)

            let termPath = viewModel.selectedRepo?.path ?? viewModel.workspacePath
            EmbeddedTerminalRepresentable(repoPath: termPath)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Dividers
    private func leftDividerBar(width: CGFloat, maximum: CGFloat) -> some View {
        Rectangle()
            .fill(isDraggingLeftDivider ? Color.accentColor : Color(NSColor.separatorColor))
            .frame(width: 4)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(coordinateSpace: .named("workbench"))
                    .onChanged { val in
                        isDraggingLeftDivider = true
                        if leftDragStart == nil { leftDragStart = width }
                        viewModel.workbenchLayout.leftDockWidth = WorkbenchDockGeometry.dragged(
                            start: leftDragStart ?? width, translation: val.translation.width,
                            minimum: 180, maximum: min(450, maximum))
                    }
                    .onEnded { _ in
                        isDraggingLeftDivider = false
                        leftDragStart = nil
                        viewModel.saveWorkbenchLayout()
                    }
            )
    }

    private func rightDividerBar(width: CGFloat, maximum: CGFloat) -> some View {
        Rectangle()
            .fill(isDraggingRightDivider ? Color.accentColor : Color(NSColor.separatorColor))
            .frame(width: 4)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(coordinateSpace: .named("workbench"))
                    .onChanged { val in
                        isDraggingRightDivider = true
                        if rightDragStart == nil { rightDragStart = width }
                        viewModel.workbenchLayout.rightDockWidth = WorkbenchDockGeometry.dragged(
                            start: rightDragStart ?? width, translation: -val.translation.width,
                            minimum: 200, maximum: min(500, maximum))
                    }
                    .onEnded { _ in
                        isDraggingRightDivider = false
                        rightDragStart = nil
                        viewModel.saveWorkbenchLayout()
                    }
            )
    }

    private func bottomDividerBar(containerHeight: CGFloat) -> some View {
        Rectangle()
            .fill(isDraggingBottomDivider ? Color.accentColor : Color(NSColor.separatorColor))
            .frame(height: 4)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(coordinateSpace: .named("workbench"))
                    .onChanged { val in
                        isDraggingBottomDivider = true
                        if bottomDragStart == nil { bottomDragStart = viewModel.workbenchLayout.bottomDockHeightRatio }
                        viewModel.workbenchLayout.bottomDockHeightRatio = WorkbenchDockGeometry.dragged(
                            start: bottomDragStart ?? 0.35, translation: -val.translation.height / max(containerHeight, 1),
                            minimum: 0.15, maximum: 0.70)
                    }
                    .onEnded { _ in
                        isDraggingBottomDivider = false
                        bottomDragStart = nil
                        viewModel.saveWorkbenchLayout()
                    }
            )
    }

    // MARK: - Git Operations
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

    private func executePush() {
        guard let repo = viewModel.selectedRepo else { return }
        isPerformingGitAction = true
        gitActionBanner = "Pushing changes for \(repo.name)..."

        DispatchQueue.global(qos: .userInitiated).async {
            let res = GitService.shared.push(repoPath: repo.path)
            DispatchQueue.main.async {
                isPerformingGitAction = false
                gitActionBanner = res.success ? (res.output.isEmpty ? "Pushed successfully." : res.output) : (res.error ?? "Push failed.")
                viewModel.refreshCurrentRepoStatus()
            }
        }
    }

    private func promptForCommitAndPush() {
        guard let repo = viewModel.selectedRepo, repo.isDirty else { return }
        commitPushMessage = ""
        isShowingCommitPushPrompt = true
    }

    private func executeAddCommitPush() {
        guard let repo = viewModel.selectedRepo else { return }
        let msg = commitPushMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { return }

        isPerformingGitAction = true
        gitActionBanner = "Staging, committing, and pushing for \(repo.name)..."

        DispatchQueue.global(qos: .userInitiated).async {
            let res = GitService.shared.addCommitPush(repoPath: repo.path, message: msg)
            DispatchQueue.main.async {
                isPerformingGitAction = false
                if res.success {
                    gitActionBanner = res.output.isEmpty ? "Committed and pushed successfully." : res.output
                } else {
                    gitActionBanner = res.error ?? "Commit & push failed."
                }
                viewModel.refreshCurrentRepoStatus()
            }
        }
    }
}
