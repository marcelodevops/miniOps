import AppKit
import SwiftUI
import SwiftTerm

@MainActor
public final class TerminalSessionManager: ObservableObject {
    public static let shared = TerminalSessionManager()

    private var sessions: [String: LocalProcessTerminalView] = [:]

    private init() {}

    public func resolveNerdFont(size: CGFloat = 13) -> NSFont {
        let preferredFamilies = [
            "JetBrainsMono Nerd Font Mono",
            "JetBrains Mono Nerd Font Mono",
            "JetBrainsMonoNL Nerd Font Mono",
            "JetBrainsMono Nerd Font",
            "JetBrainsMonoNL Nerd Font",
            "Menlo"
        ]

        let manager = NSFontManager.shared
        for family in preferredFamilies {
            if let font = manager.font(withFamily: family, traits: [], weight: 5, size: size) {
                return font
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    public func getOrCreateTerminalView(for repoPath: String) -> LocalProcessTerminalView {
        let normalized = (repoPath as NSString).expandingTildeInPath
        if let existing = sessions[normalized] {
            return existing
        }

        let terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        terminal.font = resolveNerdFont(size: 13)
        terminal.wantsLayer = true
        terminal.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = ProcessInfo.processInfo.environment
        env["MYOPS_TERMINAL"] = "1"
        env["TERM"] = "xterm-256color"
        env["LANG"] = "en_US.UTF-8"

        // Strip outer multiplexer / parent pane variables so embedded terminal
        // runs as a clean top-level interactive shell session
        env.removeValue(forKey: "HERDR_ENV")
        env.removeValue(forKey: "HERDR_PANE_ID")
        env.removeValue(forKey: "HERDR_WORKSPACE_ID")
        env.removeValue(forKey: "HERDR_TAB_ID")
        env.removeValue(forKey: "HERDR_CLIENT_SOCKET_PATH")
        env.removeValue(forKey: "HERDR_STARTUP_CWD")

        let envList = env.map { "\($0.key)=\($0.value)" }

        // Herdr mode launches (or re-attaches) a per-repo Herdr session instead of
        // a plain login shell. Falls back to the shell when herdr is unavailable.
        let launch = Self.launchCommand(for: normalized, shell: shell)

        terminal.startProcess(
            executable: launch.executable,
            args: launch.args,
            environment: envList,
            execName: nil,
            currentDirectory: normalized
        )

        sessions[normalized] = terminal
        return terminal
    }

    /// Session name derived from the repository so each repo re-attaches its own Herdr session.
    public static func herdrSessionName(for repoPath: String) -> String {
        HerdrService.sessionName(forRepoPath: repoPath)
    }

    static func launchCommand(for repoPath: String, shell: String) -> (executable: String, args: [String]) {
        guard WorkspaceStateStore.shared.getIntegrationSettings().herdrModeEnabled,
              let herdr = HerdrService.shared.findExecutable() else {
            return (shell, ["-l"])
        }
        return (herdr, ["--session", herdrSessionName(for: repoPath)])
    }

    public func hasSession(for repoPath: String) -> Bool {
        let normalized = (repoPath as NSString).expandingTildeInPath
        return sessions[normalized] != nil
    }

    public func closeSession(for repoPath: String) {
        let normalized = (repoPath as NSString).expandingTildeInPath
        if let term = sessions.removeValue(forKey: normalized) {
            // SwiftTerm's LocalProcess does not expose a public killProcess,
            // but closing its PTY / sending exit terminates the child shell cleanly.
            term.send(txt: "exit\n")
        }
    }

    /// Drops every cached session so the next terminal opens with the current launch mode.
    public func resetAllSessions() {
        for repoPath in sessions.keys {
            closeSession(for: repoPath)
        }
    }

    public func activeSessionCount() -> Int {
        sessions.count
    }

    public func processIdentifier(for repoPath: String) -> pid_t? {
        let normalized = (repoPath as NSString).expandingTildeInPath
        return sessions[normalized]?.process.shellPid
    }

    public func getSession(for repoPath: String) -> LocalProcessTerminalView? {
        let normalized = (repoPath as NSString).expandingTildeInPath
        return sessions[normalized]
    }
}

public struct EmbeddedTerminalRepresentable: NSViewRepresentable {
    public let repoPath: String

    public init(repoPath: String) {
        self.repoPath = repoPath
    }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let termView = TerminalSessionManager.shared.getOrCreateTerminalView(for: repoPath)
        termView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(termView)

        NSLayoutConstraint.activate([
            termView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            termView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            termView.topAnchor.constraint(equalTo: container.topAnchor),
            termView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        // If repoPath changed, update the subview
        let termView = TerminalSessionManager.shared.getOrCreateTerminalView(for: repoPath)
        if termView.superview !== nsView {
            nsView.subviews.forEach { $0.removeFromSuperview() }
            termView.translatesAutoresizingMaskIntoConstraints = false
            nsView.addSubview(termView)
            NSLayoutConstraint.activate([
                termView.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
                termView.trailingAnchor.constraint(equalTo: nsView.trailingAnchor),
                termView.topAnchor.constraint(equalTo: nsView.topAnchor),
                termView.bottomAnchor.constraint(equalTo: nsView.bottomAnchor)
            ])
        }
    }
}
