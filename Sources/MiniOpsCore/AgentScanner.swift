import Foundation

public final class AgentScanner: @unchecked Sendable {
    public static let shared = AgentScanner()

    private let agentTools: [(name: String, pattern: String)] = [
        ("Claude Code", "(^|/)claude(\\s|$)"),
        ("OpenAI Codex", "(^|/)codex(\\s|$)"),
        ("GitHub Copilot", "(^|/)copilot(\\s|$)"),
        ("Aider", "(^|/)aider(\\s|$)"),
        ("Antigravity", "(^|/)agy(\\s|$)|(^|/)antigravity(\\s|$)|(^|/)gemini(\\s|$)"),
        ("OpenClaw", "(^|/)openclaw(\\s|$)")
    ]

    public init() {}

    public func scanAgents(
        repositories: [RepoInfo] = [],
        sessionUsage: [String: [String: AgentUsage]]? = nil
    ) -> [AgentInfo] {
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
                psAgents = parsePsOutput(output, repositories: repositories, sessionUsage: sessionUsage)
            }
        } catch {
            psAgents = []
        }

        return mergeHerdrAgents(herdrAgents, psAgents: psAgents, repositories: repositories)
    }

    /// Scans Claude CLI JSONL logs for token usage. Privacy-safe: message/tool content is never retained.
    public func claudeSessionUsage(projectsDir: URL? = nil) -> [String: AgentUsage] {
        let baseDir = projectsDir ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard FileManager.default.fileExists(atPath: baseDir.path) else { return [:] }
        var result: [String: AgentUsage] = [:]

        guard let enumerator = FileManager.default.enumerator(
            at: baseDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var fileURLs: [(url: URL, date: Date)] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "jsonl" {
                let date = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                fileURLs.append((fileURL, date))
            }
        }
        fileURLs.sort { $0.date > $1.date }
        let topFiles = fileURLs.prefix(100)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        for item in topFiles {
            guard let handle = try? FileHandle(forReadingFrom: item.url) else { continue }
            defer { try? handle.close() }
            let fileSize = (try? handle.seekToEnd()) ?? 0
            guard fileSize > 0 else { continue }
            let tailBytes: UInt64 = min(128 * 1024, fileSize)
            try? handle.seek(toOffset: fileSize - tailBytes)
            let data = handle.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { continue }
            let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            for line in lines.reversed() {
                guard let lineData = line.data(using: .utf8),
                      let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any] else { continue }
                if let type = obj["type"] as? String, type == "assistant",
                   let cwd = obj["cwd"] as? String,
                   let msg = obj["message"] as? [String: Any],
                   let usageDict = msg["usage"] as? [String: Any] {
                    let resolvedCwd = URL(fileURLWithPath: cwd).standardized.path
                    if result[resolvedCwd] != nil { break }
                    let model = msg["model"] as? String
                    let inp = (usageDict["input_tokens"] as? Int ?? 0) +
                              (usageDict["cache_read_input_tokens"] as? Int ?? 0) +
                              (usageDict["cache_creation_input_tokens"] as? Int ?? 0)
                    let out = usageDict["output_tokens"] as? Int ?? 0
                    let total = inp + out
                    let window = 200_000
                    let pct = Double(round(Double(total) * 1000.0 / Double(window)) / 10.0)
                    result[resolvedCwd] = AgentUsage(
                        model: model,
                        contextUsedTokens: total,
                        contextWindowTokens: window,
                        contextPercent: pct,
                        usageUpdatedAt: iso.string(from: item.date)
                    )
                    break
                }
            }
        }
        return result
    }

    /// Scans Codex CLI session JSONL logs for token usage. Privacy-safe: message/tool content is never retained.
    public func codexSessionUsage(sessionsDir: URL? = nil) -> [String: AgentUsage] {
        let baseDir = sessionsDir ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard FileManager.default.fileExists(atPath: baseDir.path) else { return [:] }
        var result: [String: AgentUsage] = [:]

        guard let enumerator = FileManager.default.enumerator(
            at: baseDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var fileURLs: [(url: URL, date: Date)] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "jsonl" {
                let date = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                fileURLs.append((fileURL, date))
            }
        }
        fileURLs.sort { $0.date > $1.date }
        let topFiles = fileURLs.prefix(100)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        for item in topFiles {
            guard let handle = try? FileHandle(forReadingFrom: item.url) else { continue }
            defer { try? handle.close() }
            let fileSize = (try? handle.seekToEnd()) ?? 0
            guard fileSize > 0 else { continue }
            let readBytes: UInt64 = min(256 * 1024, fileSize)
            try? handle.seek(toOffset: fileSize - readBytes)
            let data = handle.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { continue }
            let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            var cwd: String? = nil
            var model: String? = nil
            var tokenUsage: [String: Any]? = nil
            var contextWindow: Int = 0

            for line in lines {
                guard let lineData = line.data(using: .utf8),
                      let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any] else { continue }
                let type = obj["type"] as? String
                let payload = obj["payload"] as? [String: Any] ?? [:]
                if type == "session_meta" {
                    if let c = payload["cwd"] as? String { cwd = c }
                } else if type == "turn_context" {
                    if let m = payload["model"] as? String { model = m }
                } else if type == "event_msg", let pType = payload["type"] as? String, pType == "token_count" {
                    if let info = payload["info"] as? [String: Any] {
                        tokenUsage = info["last_token_usage"] as? [String: Any]
                        contextWindow = info["model_context_window"] as? Int ?? 0
                    }
                }
            }

            if let cwd = cwd, !cwd.isEmpty {
                let resolvedCwd = URL(fileURLWithPath: cwd).standardized.path
                if result[resolvedCwd] == nil, let usage = tokenUsage {
                    let total = usage["total_tokens"] as? Int ?? 0
                    let pct = contextWindow > 0 ? Double(round(Double(total) * 1000.0 / Double(contextWindow)) / 10.0) : 0.0
                    result[resolvedCwd] = AgentUsage(
                        model: model,
                        contextUsedTokens: total,
                        contextWindowTokens: contextWindow,
                        contextPercent: pct,
                        usageUpdatedAt: iso.string(from: item.date)
                    )
                }
            }
        }
        return result
    }

    public func resolveUsage(
        tool: String,
        cwd: String?,
        sessionUsage: [String: [String: AgentUsage]]? = nil
    ) -> AgentUsage? {
        guard let cwd = cwd, !cwd.isEmpty else { return nil }
        let stdCwd = URL(fileURLWithPath: cwd).standardized.path
        let lowerTool = tool.lowercased()

        let usageMap: [String: [String: AgentUsage]]
        if let sessionUsage = sessionUsage {
            usageMap = sessionUsage
        } else {
            usageMap = [
                "claude": claudeSessionUsage(),
                "codex": codexSessionUsage()
            ]
        }

        func isPathMatch(agentPath: String, usagePath: String) -> Bool {
            if agentPath == usagePath { return true }
            let aSlash = agentPath.hasSuffix("/") ? agentPath : agentPath + "/"
            let uSlash = usagePath.hasSuffix("/") ? usagePath : usagePath + "/"
            return agentPath.hasPrefix(uSlash) || usagePath.hasPrefix(aSlash)
        }

        for (key, dict) in usageMap {
            if lowerTool.contains(key) {
                if let direct = dict[stdCwd] { return direct }
                var candidateUsages: [AgentUsage] = []
                for (usageCwd, usage) in dict {
                    if isPathMatch(agentPath: stdCwd, usagePath: usageCwd) {
                        candidateUsages.append(usage)
                    }
                }
                if candidateUsages.count == 1 {
                    return candidateUsages.first
                }
                // Ambiguous matches (multiple candidates) remain unknown (nil)
            }
        }
        return nil
    }

    public func parsePsOutput(
        _ output: String,
        repositories: [RepoInfo] = [],
        sessionUsage: [String: [String: AgentUsage]]? = nil
    ) -> [AgentInfo] {
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
            var matchedBranch: String? = nil
            var isDirty: Bool? = nil
            var isConflicted: Bool = false

            if let cwdPath = cwd {
                for repo in repositories {
                    if cwdPath.hasPrefix(repo.path) {
                        matchedRepoName = repo.name
                        matchedRepoPath = repo.path
                        matchedBranch = repo.branch
                        isDirty = repo.isDirty
                        isConflicted = repo.isMerging || repo.isRebasing || repo.isCherryPicking
                        break
                    }
                }
            }

            // Waiting heuristic: has real TTY, sleeping state, low CPU
            let hasRealTTY = tty != "??" && tty != "?"
            let isSleeping = state.hasPrefix("S") || state.hasPrefix("I")
            let isWaiting = hasRealTTY && isSleeping && cpu < 0.1

            let usage = resolveUsage(tool: toolName, cwd: cwd, sessionUsage: sessionUsage)

            agents.append(AgentInfo(
                pid: pid,
                tool: toolName,
                status: isWaiting ? "waiting" : "running",
                isWaitingForInput: isWaiting,
                elapsed: elapsed,
                runtimeSeconds: AgentInfo.parseElapsedToSeconds(elapsed),
                cpu: cpu,
                tty: tty,
                repoName: matchedRepoName,
                repoPath: matchedRepoPath,
                branch: matchedBranch,
                dirty: isDirty,
                conflicted: isConflicted,
                command: command,
                usage: usage
            ))
        }

        return agents.sorted { a, b in
            if a.isWaitingForInput != b.isWaitingForInput {
                return a.isWaitingForInput && !b.isWaitingForInput
            }
            if a.runtimeSeconds != b.runtimeSeconds {
                return a.runtimeSeconds > b.runtimeSeconds
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
            var matchedBranch: String? = nil
            var isDirty: Bool? = nil
            var isConflicted: Bool = false
            for repo in repositories {
                if effectiveCwd.hasPrefix(repo.path) {
                    matchedRepoName = repo.name
                    matchedRepoPath = repo.path
                    matchedBranch = repo.branch
                    isDirty = repo.isDirty
                    isConflicted = repo.isMerging || repo.isRebasing || repo.isCherryPicking
                    break
                }
            }

            // Try to correlate with a psAgent by tool and cwd
            var correlatedPid = 10000 + idx
            var correlatedCpu = 0.0
            var correlatedElapsed = "Herdr (\(hAgent.agentStatus))"
            var correlatedUsage: AgentUsage? = nil
            if let match = psAgents.first(where: { !matchedPsPids.contains($0.pid) && $0.tool.lowercased().contains(hAgent.agent.lowercased()) && ($0.repoPath == matchedRepoPath || matchedRepoPath == nil) }) {
                correlatedPid = match.pid
                correlatedCpu = match.cpu
                correlatedElapsed = match.elapsed
                correlatedUsage = match.usage
                matchedPsPids.insert(match.pid)
            }

            combined.append(AgentInfo(
                pid: correlatedPid,
                tool: toolName,
                status: statusText,
                isWaitingForInput: isWaiting,
                elapsed: correlatedElapsed,
                runtimeSeconds: AgentInfo.parseElapsedToSeconds(correlatedElapsed),
                cpu: correlatedCpu,
                tty: hAgent.paneId,
                repoName: matchedRepoName ?? URL(fileURLWithPath: effectiveCwd).lastPathComponent,
                repoPath: matchedRepoPath ?? effectiveCwd,
                branch: matchedBranch,
                dirty: isDirty,
                conflicted: isConflicted,
                command: hAgent.terminalTitle ?? hAgent.agent,
                usage: correlatedUsage,
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
            if a.runtimeSeconds != b.runtimeSeconds {
                return a.runtimeSeconds > b.runtimeSeconds
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
