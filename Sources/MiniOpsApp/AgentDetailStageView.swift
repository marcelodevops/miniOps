import SwiftUI
import AppKit
import MiniOpsCore

public struct AgentDetailStageView: View {
    @ObservedObject public var viewModel: WorkspaceViewModel
    @State private var liveOutputText: String = ""
    @State private var isRefreshingOutput: Bool = false

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let agent = viewModel.selectedAgent {
                agentContent(agent)
            } else {
                emptyPlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            refreshOutput()
        }
        .onChange(of: viewModel.selectedAgent?.pid) { _, _ in
            refreshOutput()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu")
                .foregroundColor(.accentColor)
                .font(.system(size: 13, weight: .bold))

            if let agent = viewModel.selectedAgent {
                Text(agent.tool)
                    .font(.system(size: 12, weight: .bold))

                Text("PID: \(agent.pid)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))

                let isRunning = agent.status == "running"
                let statusText = agent.isWaitingForInput ? "Waiting for input" : agent.status.capitalized
                Text(statusText)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundColor(agent.isWaitingForInput ? .orange : (isRunning ? .green : .secondary))
                    .background(Capsule().fill((agent.isWaitingForInput ? Color.orange : (isRunning ? Color.green : Color.secondary)).opacity(0.15)))
            } else {
                Text("Agent Detail")
                    .font(.system(size: 12, weight: .bold))
            }

            Spacer()

            if let agent = viewModel.selectedAgent {
                if let repoPath = agent.repoPath {
                    Button {
                        if let target = viewModel.repositories.first(where: { $0.path == repoPath }) {
                            viewModel.selectRepo(target)
                        }
                    } label: {
                        Label("Focus Repo", systemImage: "folder")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    refreshOutput()
                } label: {
                    Label("Refresh Output", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func agentContent(_ agent: AgentInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title and repository
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(agent.tool)
                            .font(.title3.bold())
                        Spacer()
                        Text("Elapsed: \(agent.elapsed)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let repo = agent.repoName {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text(repo)
                                .font(.system(size: 11, weight: .medium))
                            if let path = agent.repoPath {
                                Text("(\(path))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.accentColor)
                    }
                }

                Divider()

                // Metadata cards
                let isRunning = agent.status == "running"
                let statusText = agent.isWaitingForInput ? "Waiting for input" : agent.status.capitalized
                HStack(spacing: 12) {
                    metadataCard(title: "Status", value: statusText, icon: "circle.fill", iconColor: agent.isWaitingForInput ? .orange : (isRunning ? .green : .secondary))
                    metadataCard(title: "PID", value: "\(agent.pid)", icon: "number", iconColor: .accentColor)
                    metadataCard(title: "Runtime", value: agent.formattedRuntime, icon: "clock", iconColor: .blue)
                    metadataCard(title: "CPU", value: String(format: "%.1f%%", agent.cpu), icon: "gauge", iconColor: .purple)
                }

                if let repo = agent.repoName {
                    HStack(spacing: 12) {
                        metadataCard(title: "Repository", value: repo, icon: "folder", iconColor: .accentColor)
                        if let branch = agent.branch {
                            metadataCard(title: "Branch", value: branch, icon: "arrow.triangle.branch", iconColor: .teal)
                        }
                        if let pane = agent.herdrPaneId {
                            metadataCard(title: "Herdr Pane", value: pane, icon: "terminal", iconColor: .indigo)
                        }
                    }
                }

                Divider()

                // Context Usage
                VStack(alignment: .leading, spacing: 8) {
                    Text("Context Window")
                        .font(.headline)

                    if let usage = agent.usage, let pct = usage.contextPercent {
                        let used = usage.contextUsedTokens ?? 0
                        let window = usage.contextWindowTokens ?? 0
                        let isCrit = pct >= 80
                        let isWarn = pct >= 60

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(String(format: "%.1f%%", pct))
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(isCrit ? .red : (isWarn ? .orange : .primary))
                                Spacer()
                                Text("\(used.formatted()) / \(window.formatted()) tokens")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.15))
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(isCrit ? Color.red : (isWarn ? Color.orange : Color.accentColor))
                                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(pct / 100.0))))
                                }
                            }
                            .frame(height: 8)

                            if let model = usage.model {
                                HStack(spacing: 4) {
                                    Text(model)
                                        .font(.system(size: 10, weight: .medium))
                                    if let updated = usage.usageUpdatedAt {
                                        Text("· updated \(updated)")
                                            .font(.system(size: 10))
                                    }
                                }
                                .foregroundColor(.secondary)
                            }
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    } else {
                        Text("Context usage unavailable")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }
                }

                // Working tree health
                if agent.repoPath != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Working Tree")
                            .font(.subheadline.bold())
                        HStack(spacing: 6) {
                            if agent.conflicted {
                                Text("repo conflict")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.red.opacity(0.2)))
                                    .foregroundColor(.red)
                            } else if agent.dirty == true {
                                Text("repo dirty")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                                    .foregroundColor(.orange)
                            } else {
                                Text("repo clean")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.green.opacity(0.2)))
                                    .foregroundColor(.green)
                            }

                            Spacer()

                            if let path = agent.repoPath, let repo = viewModel.repositories.first(where: { $0.path == path }) {
                                Button {
                                    viewModel.selectRepo(repo)
                                    viewModel.workbenchLayout.isBottomDockCollapsed = false
                                } label: {
                                    Label("⚡ Jump to Terminal", systemImage: "terminal")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                    Divider()
                }

                // Process command / details
                VStack(alignment: .leading, spacing: 8) {
                    Text("Process Command")
                        .font(.headline)
                    Text(agent.command)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                }

                Divider()

                // Live output
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Console Output")
                            .font(.headline)
                        Spacer()
                        if isRefreshingOutput {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if !liveOutputText.isEmpty {
                        Text(liveOutputText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(NSColor.textColor))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    } else {
                        Text(agent.isHerdrManaged ? "No console output received yet." : "Direct process inspection output not available without Herdr daemon integration.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(10)
                    }
                }

                Divider()

                // Observe-only note
                Text("Observe-only: miniOps reads process metadata and usage summaries but does not send input, inspect prompts, or control this agent.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .italic()
            }
            .padding(16)
        }
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
            Image(systemName: "cpu")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No Agent Selected")
                .font(.title3.bold())
                .foregroundColor(.secondary)
            Text("Select an active coding agent from the Agents dock panel to inspect its process details and live console output here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                viewModel.showPanel(.agents)
            } label: {
                Label("Open Agents Panel", systemImage: "cpu")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refreshOutput() {
        guard let agent = viewModel.selectedAgent else {
            liveOutputText = ""
            return
        }
        if let pane = agent.herdrPaneId {
            isRefreshingOutput = true
            DispatchQueue.global(qos: .userInitiated).async {
                let out = HerdrService.shared.readPaneOutput(paneId: pane, lines: 150)
                DispatchQueue.main.async {
                    self.liveOutputText = out
                    self.isRefreshingOutput = false
                }
            }
        }
    }
}
