import SwiftUI
import MiniOpsCore

public struct TicketManagerView: View {
    public let repoPath: String
    public let tickets: [TicketInfo]
    public let onBranchCreated: () -> Void
    public let onRefresh: () -> Void

    @State private var filterOpenOnly: Bool = true
    @State private var searchText: String = ""
    @State private var actionMessage: String?
    @State private var isErrorMessage: Bool = false
    @State private var isCreatingBranch: Bool = false

    public init(repoPath: String, tickets: [TicketInfo], onBranchCreated: @escaping () -> Void, onRefresh: @escaping () -> Void) {
        self.repoPath = repoPath
        self.tickets = tickets
        self.onBranchCreated = onBranchCreated
        self.onRefresh = onRefresh
    }

    private var filteredTickets: [TicketInfo] {
        tickets.filter { t in
            if filterOpenOnly && !t.isOpen {
                return false
            }
            if !searchText.isEmpty {
                return t.key.localizedCaseInsensitiveContains(searchText) || t.summary.localizedCaseInsensitiveContains(searchText)
            }
            return true
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.accentColor)
                Text("Tasks & Tickets (\(filteredTickets.count))")
                    .font(.system(size: 12, weight: .bold))

                Spacer()

                Toggle("Open only", isOn: $filterOpenOnly)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search tickets by key or summary...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if filteredTickets.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No tickets found")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Markdown files in 'tickets/' or jira-cache.json will appear here.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredTickets) { ticket in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(ticket.key)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                .foregroundColor(.accentColor)

                            Text(ticket.status)
                                .font(.system(size: 10))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                .foregroundColor(.secondary)

                            Text(ticket.priority)
                                .font(.system(size: 10))
                                .foregroundColor(priorityColor(ticket.priority))

                            Spacer()

                            let branchName = TicketScanner.shared.makeFeatureBranchName(ticket: ticket)
                            Button(action: { createFeatureBranch(branchName: branchName) }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.branch")
                                    Text("Branch")
                                }
                                .font(.system(size: 10, weight: .semibold))
                            }
                            .disabled(isCreatingBranch)
                            .help("Create feature branch '\(branchName)'")
                        }

                        Text(ticket.summary)
                            .font(.system(size: 12))
                            .lineLimit(2)

                        let branchPreview = TicketScanner.shared.makeFeatureBranchName(ticket: ticket)
                        Text(branchPreview)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }

            if let msg = actionMessage {
                Divider()
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(isErrorMessage ? .red : .green)
                    .padding(8)
            }
        }
    }

    private func priorityColor(_ prio: String) -> Color {
        let p = prio.lowercased()
        if p.contains("high") || p.contains("urgent") || p.contains("critical") { return .red }
        if p.contains("med") { return .orange }
        return .secondary
    }

    private func createFeatureBranch(branchName: String) {
        isCreatingBranch = true
        actionMessage = "Creating feature branch \(branchName)..."
        isErrorMessage = false

        DispatchQueue.global(qos: .userInitiated).async {
            let res = GitService.shared.createBranch(repoPath: repoPath, branchName: branchName)
            DispatchQueue.main.async {
                isCreatingBranch = false
                if res.success {
                    actionMessage = "Created and checked out \(branchName)"
                    isErrorMessage = false
                    onBranchCreated()
                } else {
                    actionMessage = res.error ?? "Failed to create branch."
                    isErrorMessage = true
                }
            }
        }
    }
}
