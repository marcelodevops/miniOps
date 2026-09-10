import Foundation

public final class AgentScanner: @unchecked Sendable {
    public static let shared = AgentScanner()

    private let agentTools: [(name: String, pattern: String)] = [
        ("Claude Code", "(^|/)claude(\\s|$)"),
        ("OpenAI Codex", "(^|/)codex(\\s|$)"),
        ("Aider", "(^|/)aider(\\s|$)"),
        ("Antigravity", "(^|/)agy(\\s|$)|(^|/)antigravity(\\s|$)"),
        ("OpenClaw", "(^|/)openclaw(\\s|$)")
    ]

    public init() {}

    public func scanAgents(repositories: [RepoInfo] = []) -> [AgentInfo] {
        let herdrAgents = HerdrService.shared.fetchAgents()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,etime=,state=,tty=,%cpu=,command="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        var psAgents: [AgentInfo] = []
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                psAgents = parsePsOutput(output, repositories: repositories)
            }
        } catch {
            psAgents = []
        }

        return mergeHerdrAgents(herdrAgents, psAgents: psAgents, repositories: repositories)
    }

    public func parsePsOutput(_ output: String, repositories: [RepoInfo] = []) -> [AgentInfo] {
        var agents: [AgentInfo] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 6 else { continue }

            guard let pid = Int(parts[0]) else { continue }
            let elapsed = String(parts[1])
            let state = String(parts[2])
            let tty = String(parts[3])
            let cpu = Double(parts[4]) ?? 0.0
            let command = parts.dropFirst(5).joined(separator: " ")

            guard let toolName = identifyAgentTool(command: command) else {
                continue
            }

            // Identify CWD
            let cwd = getProcessCwd(pid: pid)
            var matchedRepoName: String? = nil
            var matchedRepoPath: String? = nil

            if let cwdPath = cwd {
                for repo in repositories {
                    if cwdPath.hasPrefix(repo.path) {
                        matchedRepoName = repo.name
                        matchedRepoPath = repo.path
                        break
                    }
                }
            }

            // Waiting heuristic: has real TTY, sleeping state, low CPU
            let hasRealTTY = tty != "??" && tty != "?"
            let isSleeping = state.hasPrefix("S") || state.hasPrefix("I")
            let isWaiting = hasRealTTY && isSleeping && cpu < 0.1

            agents.append(AgentInfo(
                pid: pid,
                tool: toolName,
                status: isWaiting ? "waiting" : "running",
                isWaitingForInput: isWaiting,
                elapsed: elapsed,
                cpu: cpu,
                tty: tty,
                repoName: matchedRepoName,
                repoPath: matchedRepoPath,
                command: command
            ))
        }

        return agents.sorted { a, b in
            if a.isWaitingForInput != b.isWaitingForInput {
                return a.isWaitingForInput && !b.isWaitingForInput
            }
            return a.pid > b.pid
        }
    }

    public func mergeHerdrAgents(
        _ herdrAgents: [HerdrAgent],
        psAgents: [AgentInfo],
        repositories: [RepoInfo] = []
    ) -> [AgentInfo] {
        var combined: [AgentInfo] = []
        var matchedPsPids: Set<Int> = []

        for (idx, hAgent) in herdrAgents.enumerated() {
            let toolName = mapHerdrToolName(hAgent.agent)
            let isWaiting = (hAgent.agentStatus.lowercased() == "blocked")
            let statusText: String
            switch hAgent.agentStatus.lowercased() {
            case "blocked": statusText = "waiting"
            case "working": statusText = "running"
            case "idle": statusText = "idle"
            case "done": statusText = "done"
            default: statusText = hAgent.agentStatus
            }

            let effectiveCwd = hAgent.foregroundCwd ?? hAgent.cwd
            var matchedRepoName: String? = nil
            var matchedRepoPath: String? = nil
            for repo in repositories {
                if effectiveCwd.hasPrefix(repo.path) {
                    matchedRepoName = repo.name
                    matchedRepoPath = repo.path
                    break
                }
            }

            // Try to correlate with a psAgent by tool and cwd
            var correlatedPid = 10000 + idx
            var correlatedCpu = 0.0
            var correlatedElapsed = "Herdr (\(hAgent.agentStatus))"
            if let match = psAgents.first(where: { !matchedPsPids.contains($0.pid) && $0.tool.lowercased().contains(hAgent.agent.lowercased()) && ($0.repoPath == matchedRepoPath || matchedRepoPath == nil) }) {
                correlatedPid = match.pid
                correlatedCpu = match.cpu
                correlatedElapsed = match.elapsed
                matchedPsPids.insert(match.pid)
            }

            combined.append(AgentInfo(
                pid: correlatedPid,
                tool: toolName,
                status: statusText,
                isWaitingForInput: isWaiting,
                elapsed: correlatedElapsed,
                cpu: correlatedCpu,
                tty: hAgent.paneId,
                repoName: matchedRepoName ?? URL(fileURLWithPath: effectiveCwd).lastPathComponent,
                repoPath: matchedRepoPath ?? effectiveCwd,
                command: hAgent.terminalTitle ?? hAgent.agent,
                herdrPaneId: hAgent.paneId,
                herdrWorkspaceId: hAgent.workspaceId,
                herdrStatus: hAgent.agentStatus,
                herdrTerminalTitle: hAgent.terminalTitle,
                isHerdrManaged: true
            ))
        }

        // Append remaining psAgents that weren't managed by Herdr
        for psAgent in psAgents where !matchedPsPids.contains(psAgent.pid) {
            combined.append(psAgent)
        }

        return combined.sorted { a, b in
            if a.isWaitingForInput != b.isWaitingForInput {
                return a.isWaitingForInput && !b.isWaitingForInput
            }
            if a.isHerdrManaged != b.isHerdrManaged {
                return a.isHerdrManaged && !b.isHerdrManaged
            }
            return a.pid > b.pid
        }
    }

    public func mapHerdrToolName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "agy", "antigravity": return "Google Antigravity"
        case "claude": return "Claude Code"
        case "codex": return "OpenAI Codex"
        case "copilot": return "GitHub Copilot"
        case "cursor": return "Cursor IDE"
        case "aider": return "Aider"
        case "openclaw": return "OpenClaw"
        case "devin": return "Devin"
        case "droid": return "Factory Droid"
        case "kimi": return "Kimi Code"
        case "qwen": return "Qwen"
        case "opencode": return "OpenCode"
        case "hermes": return "Hermes"
        case "grok": return "Grok"
        default: return raw.capitalized
        }
    }

    private func identifyAgentTool(command: String) -> String? {
        // Skip ps and grep itself
        if command.contains("ps -axo") || command.contains("grep ") {
            return nil
        }

        for (name, pattern) in agentTools {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: command.utf16.count)
                if regex.firstMatch(in: command, range: range) != nil {
                    return name
                }
            }
        }
        return nil
    }

    private func getProcessCwd(pid: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-d", "cwd", "-p", "\(pid)", "-Fn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let out = String(data: data, encoding: .utf8) else { return nil }

            for line in out.components(separatedBy: "\n") {
                if line.hasPrefix("n") {
                    return String(line.dropFirst(1)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            return nil
        }
        return nil
    }
}
