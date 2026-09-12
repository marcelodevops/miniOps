import SwiftUI
import AppKit
import MiniOpsCore

public struct TicketDetailStageView: View {
    @ObservedObject public var viewModel: WorkspaceViewModel
    @State private var localFileText: String = ""
    @State private var isLoadingLocalFile: Bool = false

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let ticket = viewModel.selectedTicket {
                ticketContent(ticket)
            } else {
                emptyPlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            loadLocalContentIfAvailable()
        }
        .onChange(of: viewModel.selectedTicket?.key) { _, _ in
            loadLocalContentIfAvailable()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "ticket.fill")
                .foregroundColor(.accentColor)
                .font(.system(size: 13, weight: .bold))

            if let ticket = viewModel.selectedTicket {
                Text(ticket.key)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))

                Text(ticket.statusCategory.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))

                Text(ticket.status)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundColor(ticket.isOpen ? .green : .secondary)
                    .background(Capsule().fill((ticket.isOpen ? Color.green : Color.secondary).opacity(0.15)))
            } else {
                Text("Ticket Detail")
                    .font(.system(size: 12, weight: .bold))
            }

            Spacer()

            if let ticket = viewModel.selectedTicket {
                Button {
                    viewModel.createBranchForTicket(ticket)
                } label: {
                    Label("Create Branch", systemImage: "arrow.triangle.branch")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if ticket.localPath != nil && ticket.localPath!.lowercased().hasSuffix(".md") {
                    Button {
                        viewModel.openTicket(ticket)
                    } label: {
                        Label("Open in Editor", systemImage: "doc.text")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let jiraURL = ticket.jiraURL, let url = URL(string: jiraURL) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open in Jira", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    let settings = viewModel.stateStore.getIntegrationSettings()
                    let cleanBase = JiraService.shared.normalizeBaseURL(settings.jiraBaseURL)
                    if !cleanBase.isEmpty, let url = URL(string: "\(cleanBase)/browse/\(ticket.key)") {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Open in Jira", systemImage: "arrow.up.forward.app")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func ticketContent(_ ticket: TicketInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title and priority
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(ticket.summary)
                            .font(.title3.bold())
                        Spacer()
                        Text("Priority: \(ticket.priority)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let path = ticket.localPath, path.lowercased().hasSuffix(".md") {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundColor(.secondary)
                    }

                    if !ticket.labels.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(ticket.labels, id: \.self) { label in
                                Text(label)
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            }
                        }
                    }
                }

                Divider()

                // Metadata cards
                HStack(spacing: 12) {
                    metadataCard(title: "Status", value: ticket.status, icon: "circle.fill", iconColor: ticket.isOpen ? .green : .secondary)
                    metadataCard(title: "Priority", value: ticket.priority, icon: "flag.fill", iconColor: .accentColor)
                    metadataCard(title: "Suggested Branch", value: TicketScanner.shared.makeFeatureBranchName(ticket: ticket), icon: "arrow.triangle.branch", iconColor: .blue)
                }
                if ticket.type != nil || ticket.project != nil || ticket.created != nil {
                    HStack(spacing: 12) {
                        if let type = ticket.type {
                            metadataCard(title: "Type", value: type, icon: "tag.fill", iconColor: .purple)
                        }
                        if let project = ticket.project {
                            metadataCard(title: "Project", value: project, icon: "folder.fill.badge.gearshape", iconColor: .indigo)
                        }
                        if let created = ticket.created {
                            metadataCard(title: ticket.isOpen ? "Open For" : "Created", value: ticket.isOpen ? Self.relativeDuration(since: created) : Self.relativeDate(created), icon: "clock.fill", iconColor: .orange)
                        }
                        if let updated = ticket.updated {
                            metadataCard(title: "Updated", value: Self.relativeDate(updated), icon: "arrow.clockwise", iconColor: .secondary)
                        }
                    }
                }

                if !relatedRepos(for: ticket).isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Related Repos (\(relatedRepos(for: ticket).count))")
                            .font(.headline)
                        Text("branch name matches \(ticket.key)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(relatedRepos(for: ticket), id: \.path) { repo in
                            HStack(spacing: 8) {
                                Text(repo.name)
                                    .font(.system(size: 12, weight: .medium))
                                Text("⎇ \(repo.branch)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                if !repo.changedFiles.isEmpty {
                                    Text("dirty")
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                                        .foregroundColor(.orange)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectRepo(repo)
                            }
                        }
                    }
                }

                Divider()

                // Content / Description
                if !localFileText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Document Preview")
                            .font(.headline)
                        Text(localFileText)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }
                } else if isLoadingLocalFile {
                    ProgressView("Loading document...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ticket Details")
                            .font(.headline)
                        Text("Key: \(ticket.key)\nSummary: \(ticket.summary)\nStatus: \(ticket.status)\nPriority: \(ticket.priority)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }
                }
            }
            .padding(16)
        }
    }

    /// Repositories whose current branch name contains the ticket key, mirroring the
    /// reference "Related repos" drawer section.
    private func relatedRepos(for ticket: TicketInfo) -> [RepoInfo] {
        viewModel.repositories.filter { $0.branch.localizedCaseInsensitiveContains(ticket.key) }
    }

    private static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func relativeDuration(since date: Date) -> String {
        let days = max(0, Date().timeIntervalSince(date) / 86400)
        return days < 1 ? "<1d" : "\(Int(days))d"
    }

    private func metadataCard(title: String, value: String, icon: String, iconColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(iconColor)
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "ticket")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No Ticket Selected")
                .font(.title3.bold())
                .foregroundColor(.secondary)
            Text("Select a ticket from the Tickets dock panel to view its details and document preview here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                viewModel.showPanel(.tickets)
            } label: {
                Label("Open Tickets Panel", systemImage: "checklist")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadLocalContentIfAvailable() {
        guard let path = viewModel.selectedTicket?.localPath else {
            localFileText = ""
            return
        }
        isLoadingLocalFile = true
        DispatchQueue.global(qos: .userInitiated).async {
            let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            DispatchQueue.main.async {
                self.localFileText = content
                self.isLoadingLocalFile = false
            }
        }
    }
}
