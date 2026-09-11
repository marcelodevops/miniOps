import SwiftUI
import AppKit
import MiniOpsCore

public struct OverviewDashboardView: View {
    @ObservedObject public var viewModel: WorkspaceViewModel
    @State private var actionMessage: String?
    @State private var isExecutingAction: Bool = false

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Workspace Header Banner
                headerBanner

                // Quick KPI Metric Tiles
                metricsGrid

                // Status message if an action was triggered
                if let msg = actionMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.accentColor)
                        Text(msg)
                            .font(.system(size: 11))
                        Spacer()
                        Button(action: { actionMessage = nil }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(8)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
                }

                // Two column sections: Attention Queue & Dirty Repositories
                HStack(alignment: .top, spacing: 16) {
                    attentionQueueSection
                    dirtyReposSection
                }

                // Quick Action Bar
                quickActionsSection
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    private var headerBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Workspace Overview")
                    .font(.system(size: 18, weight: .bold))
                Text(URL(fileURLWithPath: viewModel.workspacePath).lastPathComponent)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()

            Button(action: {
                viewModel.refreshRepositories()
                viewModel.refreshAgents()
                viewModel.syncJiraTickets()
                actionMessage = "Refreshed workspace status."
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh All")
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.bordered)
        }
    }

    private var metricsGrid: some View {
        let dirtyCount = viewModel.repositories.filter { $0.isDirty }.count
        let cleanCount = viewModel.repositories.count - dirtyCount
        let waitingAgents = viewModel.activeAgents.filter { $0.isWaitingForInput }.count
        let openTickets = viewModel.tickets.filter { $0.isOpen }.count

        return HStack(spacing: 12) {
            metricCard(
                title: "Repositories",
                value: "\(viewModel.repositories.count)",
                subtitle: "\(dirtyCount) with changes • \(cleanCount) clean",
                icon: "folder.badge.gearshape",
                color: dirtyCount > 0 ? .orange : .green
            )

            metricCard(
                title: "Autonomous Agents",
                value: "\(viewModel.activeAgents.count)",
                subtitle: waitingAgents > 0 ? "\(waitingAgents) waiting for input" : "All running smoothly",
                icon: "cpu",
                color: waitingAgents > 0 ? .red : .blue
            )

            metricCard(
                title: "Tasks & Tickets",
                value: "\(viewModel.tickets.count)",
                subtitle: "\(openTickets) open • \(viewModel.tickets.count - openTickets) done",
                icon: "checklist",
                color: .purple
            )
        }
    }

    private func metricCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text(value)
                    .font(.system(size: 22, weight: .bold))
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var attentionQueueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AGENT ATTENTION QUEUE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(viewModel.activeAgents.filter { $0.isWaitingForInput }.count) Waiting")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.orange)
            }

            let waiting = viewModel.activeAgents.filter { $0.isWaitingForInput }
            if waiting.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green.opacity(0.7))
                        .font(.system(size: 24))
                    Text("No agents waiting for input")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else {
                VStack(spacing: 6) {
                    ForEach(waiting) { agent in
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(agent.tool)
                                    .font(.system(size: 11, weight: .bold))
                                Text("Waiting in \(agent.repoName ?? "terminal") (\(agent.elapsed))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Focus") {
                                if let path = agent.repoPath, let repo = viewModel.repositories.first(where: { $0.path == path }) {
                                    viewModel.selectRepo(repo)
                                    viewModel.selectCenterTab(.editor)
                                    viewModel.workbenchLayout.isBottomDockCollapsed = false
                                }
                            }
                            .controlSize(.small)
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var dirtyReposSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let dirtyRepos = viewModel.repositories.filter { $0.isDirty }
            HStack {
                Text("REPOSITORIES NEEDING REVIEW")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(dirtyRepos.count) Modified")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(dirtyRepos.isEmpty ? .secondary : .orange)
            }

            if dirtyRepos.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green.opacity(0.7))
                        .font(.system(size: 24))
                    Text("All repositories are clean")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else {
                VStack(spacing: 6) {
                    ForEach(dirtyRepos) { repo in
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 12))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(repo.name)
                                    .font(.system(size: 11, weight: .bold))
                                Text("\(repo.changedFiles.count) changed file\(repo.changedFiles.count == 1 ? "" : "s") on \(repo.branch)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Review") {
                                viewModel.selectRepo(repo)
                                viewModel.selectCenterTab(.editor)
                                viewModel.showPanel(.changes)
                                viewModel.isGitInspectorOpen = true
                            }
                            .controlSize(.small)
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK WORKSPACE ACTIONS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Button(action: {
                    isExecutingAction = true
                    let dirtyPaths = viewModel.repositories.filter { $0.isDirty }.map { $0.path }
                    DispatchQueue.global(qos: .userInitiated).async {
                        let res = GitService.shared.batchGit(action: "reconcile", repoPaths: dirtyPaths)
                        DispatchQueue.main.async {
                            isExecutingAction = false
                            actionMessage = "Reconciled \(res.successCount) repositories."
                            viewModel.refreshRepositories()
                        }
                    }
                }) {
                    Label("Reconcile Dirty Repos", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .disabled(isExecutingAction)

                Button(action: {
                    isExecutingAction = true
                    let allPaths = viewModel.repositories.map { $0.path }
                    DispatchQueue.global(qos: .userInitiated).async {
                        let res = GitService.shared.batchGit(action: "fetch", repoPaths: allPaths)
                        DispatchQueue.main.async {
                            isExecutingAction = false
                            actionMessage = "Fetched \(res.successCount) repositories."
                            viewModel.refreshRepositories()
                        }
                    }
                }) {
                    Label("Fetch All Remotes", systemImage: "arrow.down.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .disabled(isExecutingAction)

                Button(action: {
                    viewModel.syncJiraTickets()
                }) {
                    Label("Sync Jira Tickets", systemImage: "ticket")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)

                Button(action: {
                    viewModel.isShowingCloneSheet = true
                }) {
                    Label("Clone Repository", systemImage: "plus.rectangle.on.folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 6)
    }
}
