import Foundation
import AppKit

public struct HerdrAgent: Codable, Hashable, Sendable {
    public let agent: String
    public let agentStatus: String
    public let cwd: String
    public let foregroundCwd: String?
    public let paneId: String
    public let workspaceId: String
    public let tabId: String
    public let terminalTitle: String?
    public let focused: Bool

    enum CodingKeys: String, CodingKey {
        case agent
        case agentStatus = "agent_status"
        case cwd
        case foregroundCwd = "foreground_cwd"
        case paneId = "pane_id"
        case workspaceId = "workspace_id"
        case tabId = "tab_id"
        case terminalTitle = "terminal_title"
        case focused
    }

    public init(
        agent: String,
        agentStatus: String,
        cwd: String,
        foregroundCwd: String? = nil,
        paneId: String,
        workspaceId: String,
        tabId: String,
        terminalTitle: String? = nil,
        focused: Bool = false
    ) {
        self.agent = agent
        self.agentStatus = agentStatus
        self.cwd = cwd
        self.foregroundCwd = foregroundCwd
        self.paneId = paneId
        self.workspaceId = workspaceId
        self.tabId = tabId
        self.terminalTitle = terminalTitle
        self.focused = focused
    }
}

public struct HerdrStatusInfo: Sendable {
    public let isInstalled: Bool
    public let isRunning: Bool
    public let version: String?
    public let socketPath: String?
    public let executablePath: String?

    public init(
        isInstalled: Bool,
        isRunning: Bool,
        version: String? = nil,
        socketPath: String? = nil,
        executablePath: String? = nil
    ) {
        self.isInstalled = isInstalled
        self.isRunning = isRunning
        self.version = version
        self.socketPath = socketPath
        self.executablePath = executablePath
    }
}

public struct HerdrIntegrationInfo: Identifiable, Hashable, Sendable {
    public var id: String { target }
    public let target: String
    public let displayName: String
    public let statusText: String
    public let isInstalled: Bool
    public let hookPath: String?

    public init(
        target: String,
        displayName: String,
        statusText: String,
        isInstalled: Bool,
        hookPath: String? = nil
    ) {
        self.target = target
        self.displayName = displayName
        self.statusText = statusText
        self.isInstalled = isInstalled
        self.hookPath = hookPath
    }
}

public final class HerdrService: @unchecked Sendable {
    public static let shared = HerdrService()

    private let defaultSocketPath: String
    private var cachedBinaryPath: String?

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.defaultSocketPath = "\(home)/.config/herdr/herdr.sock"
    }

    public func findExecutable() -> String? {
        if let cached = cachedBinaryPath, FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }

        let candidates = [
            "/opt/homebrew/bin/herdr",
            "/usr/local/bin/herdr",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.cargo/bin/herdr",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/herdr"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedBinaryPath = path
                return path
            }
        }

        // Fallback to searching PATH via which
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["herdr"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            cachedBinaryPath = path
            return path
        }

        return nil
    }

    public func isSocketAvailable() -> Bool {
        FileManager.default.fileExists(atPath: defaultSocketPath)
    }

    public func getHerdrStatus() -> HerdrStatusInfo {
        guard let exe = findExecutable() else {
            return HerdrStatusInfo(isInstalled: false, isRunning: false)
        }

        let socketExists = isSocketAvailable()
        let output = runHerdrCommand(["status"])
        let parsed = parseStatusOutput(output)

        return HerdrStatusInfo(
            isInstalled: true,
            isRunning: parsed.isRunning || socketExists,
            version: parsed.version,
            socketPath: parsed.socketPath ?? (socketExists ? defaultSocketPath : nil),
            executablePath: exe
        )
    }

    public func fetchAgents() -> [HerdrAgent] {
        guard findExecutable() != nil else { return [] }
        let output = runHerdrCommand(["agent", "list"])
        guard let data = output.data(using: .utf8) else { return [] }
        return parseAgentListJSON(data)
    }

    public func focusAgent(paneId: String, workspaceId: String? = nil, tabId: String? = nil) -> Bool {
        guard findExecutable() != nil else { return false }

        if let ws = workspaceId {
            _ = runHerdrCommand(["workspace", "focus", ws])
        }
        if let tab = tabId {
            _ = runHerdrCommand(["tab", "focus", tab])
        }

        _ = runHerdrCommand(["agent", "focus", paneId])

        // Bring terminal / GUI app forward if running
        activateTerminalApplication()
        return true
    }

    public func readPaneOutput(paneId: String, lines: Int = 100) -> String {
        guard findExecutable() != nil else { return "" }
        return runHerdrCommand(["pane", "read", paneId, "--source", "recent-unwrapped", "--lines", "\(lines)"])
    }

    public func getIntegrations() -> [HerdrIntegrationInfo] {
        guard findExecutable() != nil else { return [] }
        let output = runHerdrCommand(["integration", "status"])
        return parseIntegrationStatusOutput(output)
    }

    public func installIntegration(target: String) -> (success: Bool, message: String) {
        guard findExecutable() != nil else {
            return (false, "Herdr executable not found")
        }
        let out = runHerdrCommand(["integration", "install", target])
        let success = out.contains("installed") || out.contains("ensured") || out.contains("current")
        return (success, out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func uninstallIntegration(target: String) -> (success: Bool, message: String) {
        guard findExecutable() != nil else {
            return (false, "Herdr executable not found")
        }
        let out = runHerdrCommand(["integration", "uninstall", target])
        let success = out.contains("uninstalled") || out.contains("removed")
        return (success, out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Parsing Helpers (Pure & Testable)

    public func parseAgentListJSON(_ data: Data) -> [HerdrAgent] {
        struct AgentListResponse: Codable {
            struct Result: Codable {
                let agents: [HerdrAgent]
            }
            let result: Result
        }

        do {
            let decoded = try JSONDecoder().decode(AgentListResponse.self, from: data)
            return decoded.result.agents
        } catch {
            return []
        }
    }

    public func parseIntegrationStatusOutput(_ text: String) -> [HerdrIntegrationInfo] {
        var results: [HerdrIntegrationInfo] = []

        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.contains(":") else { continue }

            let parts = trimmed.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }

            let target = parts[0]
            let statusDetails = parts[1]

            // Format: "current (v8) (/Users/...)" or "not installed (/Users/...)"
            var hookPath: String? = nil
            var statusText = statusDetails

            if let openParen = statusDetails.range(of: "(/"),
               let closeParen = statusDetails.range(of: ")", range: openParen.upperBound..<statusDetails.endIndex) {
                hookPath = String(statusDetails[openParen.upperBound..<closeParen.lowerBound])
                statusText = String(statusDetails[..<openParen.lowerBound]).trimmingCharacters(in: .whitespaces)
            }

            let isInstalled = !statusText.lowercased().contains("not installed")

            results.append(HerdrIntegrationInfo(
                target: target,
                displayName: displayName(for: target),
                statusText: statusText,
                isInstalled: isInstalled,
                hookPath: hookPath
            ))
        }

        return results
    }

    public func parseStatusOutput(_ text: String) -> HerdrStatusInfo {
        var isRunning = false
        var version: String? = nil
        var socketPath: String? = nil

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("status:") && trimmed.contains("running") {
                isRunning = true
            }
            if trimmed.hasPrefix("version:") {
                let v = trimmed.replacingOccurrences(of: "version:", with: "").trimmingCharacters(in: .whitespaces)
                if !v.isEmpty { version = v }
            }
            if trimmed.hasPrefix("socket:") {
                let s = trimmed.replacingOccurrences(of: "socket:", with: "").trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { socketPath = s }
            }
        }

        return HerdrStatusInfo(
            isInstalled: true,
            isRunning: isRunning,
            version: version,
            socketPath: socketPath
        )
    }

    private func displayName(for target: String) -> String {
        switch target.lowercased() {
        case "antigravity-cli": return "Google Antigravity"
        case "claude": return "Claude Code"
        case "codex": return "OpenAI Codex"
        case "copilot": return "GitHub Copilot CLI"
        case "cursor": return "Cursor IDE"
        case "devin": return "Devin CLI"
        case "droid": return "Factory Droid"
        case "kimi": return "Kimi Code"
        case "qwen": return "Qwen Agent"
        case "opencode": return "OpenCode"
        case "hermes": return "Hermes Agent"
        case "grok": return "Grok Agent"
        case "kilo": return "Kilo Editor"
        case "mastracode": return "Mastra Code"
        default: return target.capitalized
        }
    }

    private func runHerdrCommand(_ args: [String]) -> String {
        guard let exe = findExecutable() else { return "" }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        do {
            try process.run()
            let outData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            if let str = String(data: outData, encoding: .utf8), !str.isEmpty {
                return str
            }
            return String(data: errData, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func activateTerminalApplication() {
        let terminalBundleIds = [
            "com.mitchellh.ghostty",
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "net.kovidgoyal.kitty",
            "com.alacritty"
        ]

        for bundleId in terminalBundleIds {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            if let first = apps.first {
                first.activate()
                return
            }
        }
    }
}
