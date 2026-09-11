import SwiftUI
import AppKit
import MiniOpsCore

public struct FocusWorkView: View {
    @ObservedObject public var viewModel: WorkspaceViewModel
    @State private var selectedTicketKey: String?
    @State private var actionFeedback: String?

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    private var activeTicket: TicketInfo? {
        if let key = selectedTicketKey {
            return viewModel.tickets.first(where: { $0.key == key })
        }
        // Default to first open ticket or first ticket
        return viewModel.tickets.first(where: { $0.isOpen }) ?? viewModel.tickets.first
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Focus")
                            .font(.system(size: 18, weight: .bold))
                        Text("Connected context: active ticket, working branch, and running agent.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    // Ticket selector menu
                    Menu {
                        ForEach(viewModel.tickets) { ticket in
                            Button(action: { selectedTicketKey = ticket.key }) {
                                HStack {
                                    Text("\(ticket.key): \(ticket.summary)")
                                    if ticket.key == activeTicket?.key {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checklist")
                            Text(activeTicket?.key ?? "Select Ticket")
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                }

                if let feedback = actionFeedback {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.accentColor)
                        Text(feedback)
                            .font(.system(size: 11))
                        Spacer()
                        Button(action: { actionFeedback = nil }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(8)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
                }

                if let ticket = activeTicket {
                    // 1. Primary Active Ticket Card
                    ticketCard(ticket: ticket)

                    // 2. Connected Repository & Branch Card
                    connectedRepoCard(ticket: ticket)

                    // 3. Connected Agent Card
                    connectedAgentCard
                } else {
                    emptyState
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    private func ticketCard(ticket: TicketInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(ticket.key)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundColor(.accentColor)

                Text(ticket.status)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(statusColor(ticket.statusCategory).opacity(0.15)))
                    .foregroundColor(statusColor(ticket.statusCategory))

                Text("Priority: \(ticket.priority)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    viewModel.openTicket(ticket)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Open in Jira")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
            }

            Text(ticket.summary)
                .font(.system(size: 16, weight: .semibold))

            let branchName = TicketScanner.shared.makeFeatureBranchName(ticket: ticket)
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundColor(.secondary)
                    Text(branchName)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let repo = viewModel.selectedRepo {
                    Button(action: {
                        viewModel.createBranchForTicket(ticket)
                        actionFeedback = "Created and checked out \(branchName) in \(repo.name)."
                    }) {
                        Label("Create Feature Branch", systemImage: "plus.circle")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func connectedRepoCard(ticket: TicketInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONNECTED REPOSITORY")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            if let repo = viewModel.selectedRepo {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 16))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(repo.name)
                            .font(.system(size: 13, weight: .bold))
                        HStack(spacing: 6) {
                            Text("Branch: \(repo.branch)")
                            if repo.isDirty {
                                Text("• \(repo.changedFiles.count) uncommitted changes")
                                    .foregroundColor(.orange)
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Open Changes") {
                        viewModel.selectCenterTab(.editor)
                        viewModel.showPanel(.changes)
                    }
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                HStack {
                    Text("No repository currently selected.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let first = viewModel.repositories.first {
                        Button("Select \(first.name)") {
                            viewModel.selectRepo(first)
                        }
                        .controlSize(.small)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            }
        }
    }

    private var connectedAgentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACTIVE AGENTS IN WORKSPACE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            let matchingAgents = viewModel.activeAgents.filter {
                if let repo = viewModel.selectedRepo {
                    return $0.repoPath == repo.path || $0.repoName == repo.name
                }
                return true
            }

            if matchingAgents.isEmpty {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.secondary)
                    Text("No active agent processes detected in this context.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else {
                VStack(spacing: 6) {
                    ForEach(matchingAgents) { agent in
                        HStack(spacing: 10) {
                            Image(systemName: agent.isWaitingForInput ? "exclamationmark.circle.fill" : "bolt.circle.fill")
                                .foregroundColor(agent.isWaitingForInput ? .orange : .blue)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(agent.tool)
                                    .font(.system(size: 11, weight: .bold))
                                Text("PID: \(agent.pid) • \(agent.status) • \(agent.elapsed)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Focus in Terminal") {
                                viewModel.selectCenterTab(.editor)
                                viewModel.workbenchLayout.isBottomDockCollapsed = false
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
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "target")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.6))
            Text("No Tickets Available for Focus")
                .font(.system(size: 14, weight: .semibold))
            Text("Sync Jira tickets or add markdown tickets to tickets/ to activate the focus workflow.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Button("Sync Jira Tickets") {
                viewModel.syncJiraTickets()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(8)
    }

    private func statusColor(_ category: String) -> Color {
        switch category {
        case "done": return .green
        case "in_progress": return .orange
        default: return .secondary
        }
    }
}
