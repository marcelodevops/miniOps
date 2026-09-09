import SwiftUI
import AppKit
import MiniOpsCore

public struct MainWindowView: View {
    @StateObject private var viewModel = WorkspaceViewModel()

    public init() {}

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
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 2)

                    RepoListView(
                        repos: viewModel.repositories,
                        selectedRepoPath: viewModel.selectedRepo?.path,
                        onSelectRepo: { repo in
                            viewModel.selectRepo(repo)
                        }
                    )
                }
                .frame(minHeight: 120, maxHeight: 220)

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

                    Divider()

                    // Main Content: Canvas or Git Changes Inspector
                    if viewModel.isGitInspectorOpen {
                        GitChangesView(
                            repoPath: repo.path,
                            changes: repo.changedFiles,
                            selectedFilesForCommit: $viewModel.selectedFilesForCommit,
                            onGitOperationDone: {
                                viewModel.refreshCurrentRepoStatus()
                            }
                        )
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
        .alert("Unsaved Changes", isPresented: $viewModel.showUnsavedChangesAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Discard Changes", role: .destructive) {
                viewModel.discardUnsavedChangesAndProceed()
            }
        } message: {
            Text("You have unsaved changes in the current file. Discard them to switch?")
        }
    }

    private func topToolbar(repo: RepoInfo) -> some View {
        HStack(spacing: 12) {
            // Repo info
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)
                Text(repo.name)
                    .font(.system(size: 13, weight: .bold))

                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                    Text(repo.branch)
                        .font(.system(size: 11, design: .monospaced))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))

                if repo.isDirty {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                }
            }

            Spacer()

            // View toggles
            HStack(spacing: 8) {
                // Git changes toggle
                Button(action: {
                    withAnimation {
                        viewModel.isGitInspectorOpen.toggle()
                        viewModel.saveCurrentRepoLayout()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.pull")
                        Text("Changes (\(repo.changedFiles.count))")
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
}
