import SwiftUI
import MiniOpsCore

/// Compact Jira ticket navigator for the sidebar.
///
/// Shows the tickets discovered for the current workspace/repository and lets you
/// jump straight to a ticket's local file or create its feature branch. The full
/// ticket management surface stays in the Tools → Tickets tab.
public struct TicketNavigatorView: View {
    public let tickets: [TicketInfo]
    public let selectedRepoPath: String?
    public var isSyncing: Bool = false
    public var syncStatus: String? = nil
    public let onSelectTicket: (TicketInfo) -> Void
    public let onCreateBranch: (TicketInfo) -> Void
    public let onRefresh: () -> Void

    @Binding public var isExpanded: Bool
    @State private var searchText: String = ""
    @State private var openOnly: Bool = true

    public init(
        tickets: [TicketInfo],
        selectedRepoPath: String?,
        isExpanded: Binding<Bool>,
        isSyncing: Bool = false,
        syncStatus: String? = nil,
        onSelectTicket: @escaping (TicketInfo) -> Void,
        onCreateBranch: @escaping (TicketInfo) -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.tickets = tickets
        self.selectedRepoPath = selectedRepoPath
        self._isExpanded = isExpanded
        self.isSyncing = isSyncing
        self.syncStatus = syncStatus
        self.onSelectTicket = onSelectTicket
        self.onCreateBranch = onCreateBranch
        self.onRefresh = onRefresh
    }

    var filteredTickets: [TicketInfo] {
        TicketScanner.shared.filter(tickets: tickets, searchText: searchText, openOnly: openOnly)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                Divider()
                searchBar
                Divider()
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Text("JIRA TICKETS (\(filteredTickets.count))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .help(isExpanded ? "Collapse ticket navigator" : "Expand ticket navigator")

            Spacer()

            if isSyncing {
                ProgressView()
                    .controlSize(.mini)
                    .help("Syncing Jira tickets…")
            }

            if let status = syncStatus {
                Text(status)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
            }
            .disabled(isSyncing)
            .buttonStyle(.borderless)
            .help("Rescan and sync Jira tickets")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            TextField("Find a ticket…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))

            Toggle("Open", isOn: $openOnly)
                .toggleStyle(.checkbox)
                .font(.system(size: 10))
                .help("Show only tickets that are not done")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        if filteredTickets.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
                Text(tickets.isEmpty ? "No tickets found in this workspace" : "No tickets match this filter")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredTickets) { ticket in
                        TicketNavigatorRow(
                            ticket: ticket,
                            canCreateBranch: selectedRepoPath != nil,
                            onSelect: { onSelectTicket(ticket) },
                            onCreateBranch: { onCreateBranch(ticket) }
                        )
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }
}

private struct TicketNavigatorRow: View {
    let ticket: TicketInfo
    let canCreateBranch: Bool
    let onSelect: () -> Void
    let onCreateBranch: () -> Void

    @State private var isHovering: Bool = false

    private var statusColor: Color {
        switch ticket.statusCategory {
        case "done": return .green
        case "in_progress": return .orange
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(ticket.key)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
                Text(ticket.summary)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            if isHovering && canCreateBranch {
                Button(action: onCreateBranch) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("Create feature branch \(TicketScanner.shared.makeFeatureBranchName(ticket: ticket))")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
        .help(ticket.localPath == nil ? "\(ticket.key): \(ticket.summary)" : "Open \(ticket.key)")
        .contextMenu {
            if canCreateBranch {
                Button("Create Feature Branch") { onCreateBranch() }
            }
            if ticket.localPath != nil {
                Button("Open Ticket File") { onSelect() }
            }
            Button("Copy Ticket Key") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ticket.key, forType: .string)
            }
        }
    }
}
