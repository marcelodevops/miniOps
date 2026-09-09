import SwiftUI
import AppKit
import MiniOpsCore

public struct MenuBarExtraView: View {
    @ObservedObject public var viewModel: WorkspaceViewModel
    @State private var isPerformingAction: Bool = false
    @State private var actionStatus: String?

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    private var dirtyRepos: [RepoInfo] {
        viewModel.repositories.filter { $0.isDirty }
    }

    private var statusSummary: WorkspaceStatusSummary {
        let waiting = viewModel.activeAgents.filter { $0.isWaitingForInput }.count
        return WorkspaceStatusSummary(dirtyCount: dirtyRepos.count, waitingAgentCount: waiting)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Status
            HStack(spacing: 8) {
                Image(systemName: statusSummary.iconName)
                    .foregroundColor(statusColor)
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 1) {
                    Text("miniOps")
                        .font(.system(size: 13, weight: .bold))
                    Text(statusSummary.tooltip)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 2)

            Divider()

            // List of dirty repos if any
            if !dirtyRepos.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uncommitted Changes:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    ForEach(dirtyRepos.prefix(5)) { repo in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                            Text(repo.name)
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text(repo.branch)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text("\(repo.changedFiles.count) files")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    if dirtyRepos.count > 5 {
                        Text("+ \(dirtyRepos.count - 5) more repos")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)

                Divider()
            }

            // Quick Actions
            VStack(alignment: .leading, spacing: 6) {
                Button(action: bringAppToFront) {
                    Label("Open miniOps Window", systemImage: "macwindow")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if !dirtyRepos.isEmpty {
                    Button(action: reconcileDirtyRepos) {
                        Label("Reconcile All Dirty (\(dirtyRepos.count))", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPerformingAction)
                }

                Button(action: fetchAllRepos) {
                    Label("Fetch All Repositories", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(isPerformingAction)

                Button(action: { viewModel.refreshRepositories() }) {
                    Label("Rescan Workspace", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if let status = actionStatus {
                Divider()
                Text(status)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Quit
            Button(role: .destructive, action: { NSApp.terminate(nil) }) {
                Label("Quit miniOps", systemImage: "power")
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 280)
    }

    private var statusColor: Color {
        switch statusSummary.type {
        case .clean: return .green
        case .dirtyRepos: return .orange
        case .agentWaiting: return .red
        case .offline: return .secondary
        }
    }

    private func bringAppToFront() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }

    private func reconcileDirtyRepos() {
        isPerformingAction = true
        actionStatus = "Reconciling dirty repositories..."

        let dirtyPaths = dirtyRepos.map { $0.path }
        DispatchQueue.global(qos: .userInitiated).async {
            let res = GitService.shared.batchGit(action: "reconcile", repoPaths: dirtyPaths)
            DispatchQueue.main.async {
                isPerformingAction = false
                actionStatus = "Reconcile done: \(res.successCount) succeeded, \(res.failureCount) failed"
                NotificationService.shared.sendNotification(
                    title: "miniOps: Reconcile Complete",
                    body: "Reconciled \(res.successCount) dirty repos (\(res.failureCount) failed)."
                )
                viewModel.refreshRepositories()
            }
        }
    }

    private func fetchAllRepos() {
        isPerformingAction = true
        actionStatus = "Fetching all repositories..."

        let allPaths = viewModel.repositories.map { $0.path }
        DispatchQueue.global(qos: .userInitiated).async {
            let res = GitService.shared.batchGit(action: "fetch", repoPaths: allPaths)
            DispatchQueue.main.async {
                isPerformingAction = false
                actionStatus = "Fetch done: \(res.successCount) succeeded, \(res.failureCount) failed"
                NotificationService.shared.sendNotification(
                    title: "miniOps: Fetch Complete",
                    body: "Fetched \(res.successCount) repos (\(res.failureCount) failed)."
                )
                viewModel.refreshRepositories()
            }
        }
    }
}
