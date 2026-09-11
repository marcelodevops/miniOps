import SwiftUI
import AppKit
import MiniOpsCore

public struct WorkbenchStatusBarView: View {
    @ObservedObject public var viewModel: WorkspaceViewModel

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Left: Repo & Branch info
            HStack(spacing: 6) {
                if let repo = viewModel.selectedRepo {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                    Text(repo.name)
                        .font(.system(size: 11, weight: .bold))

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
                            .frame(width: 6, height: 6)
                            .help("Uncommitted changes")
                    }

                    if repo.ahead > 0 || repo.behind > 0 {
                        HStack(spacing: 2) {
                            if repo.ahead > 0 {
                                Text("↑\(repo.ahead)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                            if repo.behind > 0 {
                                Text("↓\(repo.behind)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                } else {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("No repo selected")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Divider().frame(height: 12)

            // Center: Agent status summary & Freshness
            HStack(spacing: 10) {
                let waitingCount = viewModel.activeAgents.filter { $0.isWaitingForInput }.count
                if waitingCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("\(waitingCount) agent\(waitingCount == 1 ? "" : "s") waiting")
                            .foregroundColor(.orange)
                    }
                    .font(.system(size: 11, weight: .semibold))
                } else if !viewModel.activeAgents.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "cpu")
                            .foregroundColor(.secondary)
                        Text("\(viewModel.activeAgents.count) agent\(viewModel.activeAgents.count == 1 ? "" : "s") running")
                            .foregroundColor(.secondary)
                    }
                    .font(.system(size: 11))
                }

                if let syncStatus = viewModel.ticketSyncStatus {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9))
                            .foregroundColor(.accentColor)
                        Text(syncStatus)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Right: Center Tabs switcher + Dock toggle controls
            HStack(spacing: 8) {
                // Center Tab quick-switch pills
                Picker("", selection: Binding(
                    get: { viewModel.workbenchLayout.activeCenterTab },
                    set: { viewModel.selectCenterTab($0) }
                )) {
                    ForEach(CenterTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .fixedSize()

                Divider().frame(height: 12)

                // Dock toggles
                HStack(spacing: 3) {
                    Button(action: { viewModel.toggleLeftDock() }) {
                        Image(systemName: viewModel.workbenchLayout.isLeftDockCollapsed ? "sidebar.left" : "sidebar.leading")
                            .font(.system(size: 11))
                            .foregroundColor(viewModel.workbenchLayout.isLeftDockCollapsed ? .secondary : .accentColor)
                    }
                    .buttonStyle(.borderless)
                    .help(viewModel.workbenchLayout.isLeftDockCollapsed ? "Show Left Dock (Cmd+1)" : "Hide Left Dock (Cmd+1)")

                    Button(action: { viewModel.toggleBottomDock() }) {
                        Image(systemName: "terminal")
                            .font(.system(size: 11))
                            .foregroundColor(viewModel.workbenchLayout.isBottomDockCollapsed ? .secondary : .accentColor)
                    }
                    .buttonStyle(.borderless)
                    .help(viewModel.workbenchLayout.isBottomDockCollapsed ? "Show Terminal (Cmd+J)" : "Hide Terminal (Cmd+J)")

                    Button(action: { viewModel.toggleRightDock() }) {
                        Image(systemName: viewModel.workbenchLayout.isRightDockCollapsed ? "sidebar.right" : "sidebar.trailing")
                            .font(.system(size: 11))
                            .foregroundColor(viewModel.workbenchLayout.isRightDockCollapsed ? .secondary : .accentColor)
                    }
                    .buttonStyle(.borderless)
                    .help(viewModel.workbenchLayout.isRightDockCollapsed ? "Show Tools Dock (Cmd+3)" : "Hide Tools Dock (Cmd+3)")
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider(), alignment: .top)
    }
}
