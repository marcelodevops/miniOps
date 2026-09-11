import SwiftUI
import AppKit
import MiniOpsCore

public struct AgentInspectorView: View {
    public let agents: [AgentInfo]
    public let onSelectRepo: (String) -> Void
    public let onRefresh: () -> Void
    public var onSelectAgent: ((AgentInfo) -> Void)?

    @State private var inspectingAgent: AgentInfo?
    @State private var liveOutputText: String = ""
    @State private var isLoadingOutput: Bool = false
    @State private var herdrStatus: HerdrStatusInfo = HerdrService.shared.getHerdrStatus()

    public init(
        agents: [AgentInfo],
        onSelectRepo: @escaping (String) -> Void,
        onRefresh: @escaping () -> Void,
        onSelectAgent: ((AgentInfo) -> Void)? = nil
    ) {
        self.agents = agents
        self.onSelectRepo = onSelectRepo
        self.onRefresh = onRefresh
        self.onSelectAgent = onSelectAgent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(.accentColor)
                Text("Active Coding Agents (\(agents.count))")
                    .font(.system(size: 12, weight: .bold))

                Spacer()

                if herdrStatus.isRunning {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Herdr Connected")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                    .help("Herdr daemon is active at \(herdrStatus.socketPath ?? "herdr.sock")")
                }

                Button(action: {
                    herdrStatus = HerdrService.shared.getHerdrStatus()
                    onRefresh()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Refresh agent processes")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if agents.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No local coding agents detected")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Agents started in terminal (Claude, Codex, Aider, Antigravity) or managed by Herdr will appear here.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(agents) { agent in
                    VStack(alignment: .leading, spacing: 6) {
                        // Title row
                        HStack(spacing: 6) {
                            Circle()
                                .fill(agent.isWaitingForInput ? Color.red : (agent.status == "running" ? Color.green : Color.blue))
                                .frame(width: 8, height: 8)

                            Text(agent.tool)
                                .font(.system(size: 12, weight: .bold))

                            if agent.isHerdrManaged {
                                HStack(spacing: 3) {
                                    Image(systemName: "terminal")
                                        .font(.system(size: 8))
                                    Text("HERDR")
                                        .font(.system(size: 8, weight: .heavy))
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.purple.opacity(0.18)))
                                .foregroundColor(.purple)
                                .help("Managed by Herdr in pane \(agent.herdrPaneId ?? "")")
                            }

                            Spacer()

                            let badgeColor: Color = agent.isWaitingForInput ? .red : (agent.status == "running" ? .green : .blue)
                            let badgeText: String = agent.isWaitingForInput ? "WAITING FOR INPUT" : agent.status.uppercased()

                            Text(badgeText)
                                .font(.system(size: 9, weight: .heavy))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(badgeColor.opacity(0.15)))
                                .foregroundColor(badgeColor)
                        }

                        // Subtitle / Herdr task title
                        if let title = agent.herdrTerminalTitle, !title.isEmpty {
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }

                        // Process details row
                        HStack(spacing: 8) {
                            if let pane = agent.herdrPaneId {
                                Text("Pane: \(pane)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            if let ws = agent.herdrWorkspaceId {
                                Text("WS: \(ws)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Text("PID: \(agent.pid)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)

                            Text("Time: \(agent.elapsed)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)

                            if agent.cpu > 0.0 {
                                Text(String(format: "CPU: %.1f%%", agent.cpu))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Repo path and focus buttons
                        HStack(spacing: 6) {
                            if let repo = agent.repoName {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 10))
                                    Text(repo)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.accentColor)
                            }

                            Spacer()

                            if let onSelectAgent {
                                Button("Detail") {
                                    onSelectAgent(agent)
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10, weight: .semibold))
                            }

                            if let path = agent.repoPath {
                                Button("Focus Repo") {
                                    onSelectRepo(path)
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10, weight: .semibold))
                            }

                            if agent.isHerdrManaged, let pane = agent.herdrPaneId {
                                Button(action: {
                                    inspectLiveOutput(agent: agent)
                                }) {
                                    Label("Live Output", systemImage: "doc.text.magnifyingglass")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button(action: {
                                    _ = HerdrService.shared.focusAgent(
                                        paneId: pane,
                                        workspaceId: agent.herdrWorkspaceId
                                    )
                                }) {
                                    Label("Jump in Terminal", systemImage: "arrow.up.forward.app")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .help("Focus this agent's pane in Herdr and bring terminal to front")
                            }
                        }

                        if !agent.isHerdrManaged {
                            Text(agent.command)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.7))
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $inspectingAgent) { agent in
            HerdrOutputSheetView(
                agent: agent,
                initialOutput: liveOutputText,
                onDismiss: {
                    inspectingAgent = nil
                }
            )
        }
    }

    private func inspectLiveOutput(agent: AgentInfo) {
        guard let pane = agent.herdrPaneId else { return }
        liveOutputText = HerdrService.shared.readPaneOutput(paneId: pane, lines: 120)
        inspectingAgent = agent
    }
}

private struct HerdrOutputSheetView: View {
    let agent: AgentInfo
    let initialOutput: String
    let onDismiss: () -> Void

    @State private var output: String = ""
    @State private var lineCount: Int = 100
    @State private var isRefreshing: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Sheet Header
            HStack(spacing: 10) {
                Image(systemName: "terminal")
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(agent.tool)
                            .font(.system(size: 13, weight: .bold))
                        if let pane = agent.herdrPaneId {
                            Text("(\(pane))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    if let title = agent.herdrTerminalTitle {
                        Text(title)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Picker("Lines", selection: $lineCount) {
                    Text("50 lines").tag(50)
                    Text("100 lines").tag(100)
                    Text("200 lines").tag(200)
                    Text("500 lines").tag(500)
                }
                .pickerStyle(.menu)
                .frame(width: 110)
                .onChange(of: lineCount) { _, _ in
                    refreshOutput()
                }

                Button(action: refreshOutput) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh terminal buffer")

                Button(action: {
                    if let pane = agent.herdrPaneId {
                        _ = HerdrService.shared.focusAgent(paneId: pane, workspaceId: agent.herdrWorkspaceId)
                    }
                }) {
                    Label("Focus in Terminal", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Close", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Terminal Output Content
            ScrollView([.horizontal, .vertical]) {
                Text(output.isEmpty ? "No output available in pane buffer." : output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .textSelection(.enabled)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(minWidth: 680, idealWidth: 780, minHeight: 440, idealHeight: 520)
        .onAppear {
            output = initialOutput.isEmpty ? (agent.herdrPaneId.map { HerdrService.shared.readPaneOutput(paneId: $0, lines: lineCount) } ?? "") : initialOutput
        }
    }

    private func refreshOutput() {
        guard let pane = agent.herdrPaneId else { return }
        output = HerdrService.shared.readPaneOutput(paneId: pane, lines: lineCount)
    }
}
