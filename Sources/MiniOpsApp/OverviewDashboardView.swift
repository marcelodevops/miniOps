import SwiftUI
import AppKit
import MiniOpsCore

private struct DonutSegment: Identifiable {
    var id: String { label }
    let label: String
    let count: Int
    let color: Color
    let start: Double
    let end: Double
}

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

                // Reference Overview Charts
                chartsSection

                // Attention Sections: Repos, Tickets, and Agents
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        dirtyReposSection
                        attentionQueueSection
                    }
                    .frame(maxWidth: .infinity)

                    attentionTicketsSection
                        .frame(maxWidth: .infinity)
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
                color: dirtyCount > 0 ? .orange : .green,
                action: {
                    viewModel.showRepositories(filter: dirtyCount > 0 ? .dirty : .all)
                }
            )

            metricCard(
                title: "Autonomous Agents",
                value: "\(viewModel.activeAgents.count)",
                subtitle: waitingAgents > 0 ? "\(waitingAgents) waiting for input" : "All running smoothly",
                icon: "cpu",
                color: waitingAgents > 0 ? .red : .blue,
                action: {
                    viewModel.showAgents(filter: waitingAgents > 0 ? .waiting : .all)
                }
            )

            metricCard(
                title: "Tasks & Tickets",
                value: "\(viewModel.tickets.count)",
                subtitle: "\(openTickets) open • \(viewModel.tickets.count - openTickets) done",
                icon: "checklist",
                color: .purple,
                action: {
                    viewModel.showTickets(filter: openTickets > 0 ? .open : .all)
                }
            )
        }
    }

    private func metricCard(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open the filtered \(title.lowercased()) panel")
    }

    // MARK: - Reference Overview Charts

    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WORKSPACE ANALYTICS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                chartCard(title: "Tickets by State", icon: "chart.pie.fill") {
                    donutChart
                }

                chartCard(title: "Tickets by Priority", icon: "chart.bar.fill") {
                    priorityBarsChart
                }

                chartCard(title: "Repositories by Type", icon: "square.grid.2x2.fill") {
                    repoTypeBarsChart
                }

                chartCard(title: "Repositories by Origin", icon: "network") {
                    repoOriginBarsChart
                }
            }
        }
    }

    private func chartCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var donutSegments: [DonutSegment] {
        let total = viewModel.tickets.count
        guard total > 0 else { return [] }
        var current: Double = 0
        var result: [DonutSegment] = []
        for item in viewModel.ticketsByCategory {
            guard item.count > 0 else { continue }
            let fraction = Double(item.count) / Double(total)
            let color = categoryColor(item.category)
            result.append(DonutSegment(
                label: item.category,
                count: item.count,
                color: color,
                start: current,
                end: current + fraction
            ))
            current += fraction
        }
        return result
    }

    private var donutChart: some View {
        let segments = donutSegments
        let total = viewModel.tickets.count
        return VStack(spacing: 12) {
            if total == 0 {
                emptyChartNotice(message: "No tickets recorded")
            } else {
                ZStack {
                    ForEach(segments) { seg in
                        Circle()
                            .trim(from: CGFloat(seg.start), to: CGFloat(seg.end))
                            .stroke(seg.color, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                            .contentShape(Circle().stroke(lineWidth: 14))
                            .onTapGesture {
                                viewModel.showTickets(filter: .category(seg.label))
                            }
                    }
                    VStack(spacing: 0) {
                        Text("\(total)")
                            .font(.system(size: 20, weight: .bold))
                        Text(total == 1 ? "ticket" : "tickets")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 90, height: 90)
                .padding(.top, 4)

                // Legend
                HStack(spacing: 8) {
                    ForEach(viewModel.ticketsByCategory, id: \.category) { item in
                        Button(action: {
                            viewModel.showTickets(filter: .category(item.category))
                        }) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(categoryColor(item.category))
                                    .frame(width: 7, height: 7)
                                Text(item.category)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text("\(item.count)")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var priorityBarsChart: some View {
        let items = viewModel.ticketsByPriority
        let maxCount = max(1, items.map(\.count).max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            if items.isEmpty || viewModel.tickets.isEmpty {
                emptyChartNotice(message: "No tickets recorded")
            } else {
                ForEach(items.prefix(5), id: \.priority) { item in
                    horizontalBarRow(
                        label: item.priority,
                        count: item.count,
                        maxCount: maxCount,
                        color: priorityColor(item.priority),
                        action: {
                            viewModel.showTickets(filter: .priority(item.priority))
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var repoTypeBarsChart: some View {
        let items = viewModel.reposByType
        let maxCount = max(1, items.map(\.count).max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            if items.isEmpty || viewModel.repositories.isEmpty {
                emptyChartNotice(message: "No repositories recorded")
            } else {
                ForEach(items.prefix(5), id: \.tag) { item in
                    horizontalBarRow(
                        label: item.tag,
                        count: item.count,
                        maxCount: maxCount,
                        color: Color.accentColor,
                        action: {
                            viewModel.showRepositories(filter: .tag(item.tag))
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var repoOriginBarsChart: some View {
        let items = viewModel.reposByOrigin
        let maxCount = max(1, items.map(\.count).max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            if items.isEmpty || viewModel.repositories.isEmpty {
                emptyChartNotice(message: "No repositories recorded")
            } else {
                ForEach(items.prefix(5), id: \.origin) { item in
                    horizontalBarRow(
                        label: item.origin,
                        count: item.count,
                        maxCount: maxCount,
                        color: originColor(item.origin),
                        action: {
                            viewModel.showRepositories(filter: .origin(item.origin))
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "Done": return .green
        case "In Progress": return .orange
        default: return Color(NSColor.systemGray)
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority.lowercased() {
        case "highest", "high": return .red
        case "medium": return .orange
        case "low", "lowest": return .green
        default: return .secondary
        }
    }

    private func originColor(_ origin: String) -> Color {
        switch origin.lowercased() {
        case "github": return Color.blue
        case "gitlab": return Color.orange
        case "bitbucket": return Color.indigo
        default: return Color.accentColor
        }
    }

    private func emptyChartNotice(message: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "chart.bar")
                .font(.system(size: 20))
                .foregroundColor(.secondary.opacity(0.6))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func horizontalBarRow(
        label: String,
        count: Int,
        maxCount: Int,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 85, alignment: .leading)
                    .lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(NSColor.separatorColor).opacity(0.25))
                            .frame(height: 14)
                        let ratio = CGFloat(count) / CGFloat(maxCount)
                        let barWidth = count > 0 ? max(6.0, geo.size.width * ratio) : 0
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(0.85))
                            .frame(width: barWidth, height: 14)
                    }
                }
                .frame(height: 14)

                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to filter by \(label)")
    }

    // MARK: - Attention Sections

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
            let attentionRepos = viewModel.repositories
                .filter { $0.attentionScore > 0 }
                .sorted { $0.attentionScore > $1.attentionScore }

            HStack {
                Text("REPOSITORIES NEEDING ATTENTION")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(attentionRepos.count) Need Attention")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(attentionRepos.isEmpty ? .secondary : .orange)
            }

            if attentionRepos.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green.opacity(0.7))
                        .font(.system(size: 24))
                    Text("All repositories are clean and up to date")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else {
                VStack(spacing: 6) {
                    ForEach(attentionRepos.prefix(12)) { repo in
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.name)
                                    .font(.system(size: 11, weight: .bold))
                                HStack(spacing: 4) {
                                    ForEach(repo.attentionReasons, id: \.self) { reason in
                                        let isWarn = reason.contains("dirty") || reason.contains("merge") || reason.contains("rebase") || reason.contains("cherry-pick") || reason.contains("behind")
                                        Text(reason)
                                            .font(.system(size: 9, weight: .semibold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(isWarn ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.15))
                                            .foregroundColor(isWarn ? .orange : .secondary)
                                            .cornerRadius(3)
                                    }
                                    Text("on \(repo.branch)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
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


    private var attentionTicketsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let openTickets = viewModel.tickets
                .filter { $0.isOpen }
                .sorted { a, b in
                    if a.daysOpen == b.daysOpen {
                        return a.key < b.key
                    }
                    return a.daysOpen > b.daysOpen
                }
            HStack {
                Text("TICKETS NEEDING ATTENTION")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(openTickets.count) Open")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(openTickets.isEmpty ? .secondary : .purple)
            }

            if openTickets.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green.opacity(0.7))
                        .font(.system(size: 24))
                    Text("No open tickets right now")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else {
                VStack(spacing: 6) {
                    ForEach(openTickets.prefix(12)) { ticket in
                        HStack(spacing: 8) {
                            Text(ticket.key)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.accentColor)
                                .frame(width: 75, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ticket.summary)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    let band = ticket.ageBand
                                    Text(band.label)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(band.isCritical ? Color.red.opacity(0.2) : (band.isStale ? Color.orange.opacity(0.2) : Color.green.opacity(0.2)))
                                        .foregroundColor(band.isCritical ? .red : (band.isStale ? .orange : .green))
                                        .cornerRadius(3)

                                    Text(ticket.status)
                                        .font(.system(size: 9))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.15))
                                        .cornerRadius(3)

                                    Text(ticket.normalizedPriority)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(priorityColor(ticket.normalizedPriority))
                                }
                            }
                            Spacer()
                            Button("Focus") {
                                viewModel.selectFocusTicket(ticket)
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
