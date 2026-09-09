import SwiftUI
import MiniOpsCore

public struct AgentInspectorView: View {
    public let agents: [AgentInfo]
    public let onSelectRepo: (String) -> Void
    public let onRefresh: () -> Void

    public init(agents: [AgentInfo], onSelectRepo: @escaping (String) -> Void, onRefresh: @escaping () -> Void) {
        self.agents = agents
        self.onSelectRepo = onSelectRepo
        self.onRefresh = onRefresh
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
                Button(action: onRefresh) {
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
                    Text("Agents started in terminal (Claude, Codex, Aider, Antigravity) will appear here.")
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
                        HStack(spacing: 6) {
                            // Status indicator
                            Circle()
                                .fill(agent.isWaitingForInput ? Color.red : Color.green)
                                .frame(width: 8, height: 8)

                            Text(agent.tool)
                                .font(.system(size: 12, weight: .bold))

                            Spacer()

                            Text(agent.isWaitingForInput ? "WAITING FOR INPUT" : "RUNNING")
                                .font(.system(size: 9, weight: .heavy))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(agent.isWaitingForInput ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                                )
                                .foregroundColor(agent.isWaitingForInput ? .red : .green)
                        }

                        HStack(spacing: 10) {
                            Text("PID: \(agent.pid)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)

                            Text("TTY: \(agent.tty)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)

                            Text("Time: \(agent.elapsed)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)

                            Text(String(format: "CPU: %.1f%%", agent.cpu))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        if let repo = agent.repoName {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                    .font(.system(size: 10))
                                Text(repo)
                                    .font(.system(size: 11, weight: .medium))

                                Spacer()

                                if let path = agent.repoPath {
                                    Button("Focus Repo") {
                                        onSelectRepo(path)
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 10, weight: .semibold))
                                }
                            }
                            .foregroundColor(.accentColor)
                        }

                        Text(agent.command)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
    }
}
