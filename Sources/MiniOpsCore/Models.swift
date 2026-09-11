import Foundation

public struct GitFileChange: Codable, Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let statusLetter: String // "M", "A", "D", "??", "R", etc.
    public let isStaged: Bool
    public let isUntracked: Bool

    public init(path: String, statusLetter: String, isStaged: Bool, isUntracked: Bool) {
        self.path = path
        self.statusLetter = statusLetter
        self.isStaged = isStaged
        self.isUntracked = isUntracked
    }
}

public struct RepoInfo: Codable, Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let groupName: String?
    public var branch: String
    public var isDirty: Bool
    public var ahead: Int
    public var behind: Int
    public var changedFiles: [GitFileChange]

    public init(
        name: String,
        path: String,
        groupName: String? = nil,
        branch: String = "main",
        isDirty: Bool = false,
        ahead: Int = 0,
        behind: Int = 0,
        changedFiles: [GitFileChange] = []
    ) {
        self.name = name
        self.path = path
        self.groupName = groupName
        self.branch = branch
        self.isDirty = isDirty
        self.ahead = ahead
        self.behind = behind
        self.changedFiles = changedFiles
    }
}

public enum FileNodeType: String, Codable, Sendable {
    case file
    case directory
}

public struct FileNode: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public var children: [FileNode]?

    public init(name: String, path: String, isDirectory: Bool, children: [FileNode]? = nil) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.children = children
    }
}

public struct RepoLayoutState: Codable, Hashable, Sendable {
    public var selectedFilePath: String?
    public var expandedFolderPaths: Set<String>
    public var terminalHeightRatio: Double // e.g. 0.5 for equal split
    public var isEditorCollapsed: Bool
    public var isTerminalCollapsed: Bool
    public var isGitInspectorOpen: Bool

    public init(
        selectedFilePath: String? = nil,
        expandedFolderPaths: Set<String> = [],
        terminalHeightRatio: Double = 0.5,
        isEditorCollapsed: Bool = false,
        isTerminalCollapsed: Bool = false,
        isGitInspectorOpen: Bool = false
    ) {
        self.selectedFilePath = selectedFilePath
        self.expandedFolderPaths = expandedFolderPaths
        self.terminalHeightRatio = terminalHeightRatio
        self.isEditorCollapsed = isEditorCollapsed
        self.isTerminalCollapsed = isTerminalCollapsed
        self.isGitInspectorOpen = isGitInspectorOpen
    }
}

public enum CenterTab: String, Codable, CaseIterable, Sendable {
    case editor = "Editor"
    case overview = "Overview"
    case focus = "Focus"
    case graph = "Graph"
}

public enum WorkbenchPanel: String, Codable, CaseIterable, Sendable {
    case repos = "Repositories"
    case tickets = "Tickets"
    case changes = "Changes"
    case agents = "Agents"
    case stashes = "Stashes"
    case worktrees = "Worktrees"
    case notes = "Notes"
}

public typealias LeftDockTab = WorkbenchPanel
public typealias RightDockTab = WorkbenchPanel
public enum SideDock: String, Codable, Sendable { case left, right }

public struct WorkbenchLayoutState: Codable, Hashable, Sendable {
    public var panelLocations: [String: SideDock]?
    public var activeCenterTab: CenterTab
    public var activeLeftTab: LeftDockTab
    public var activeRightTab: RightDockTab
    public var isLeftDockCollapsed: Bool
    public var isRightDockCollapsed: Bool
    public var isBottomDockCollapsed: Bool
    public var leftDockWidth: Double
    public var rightDockWidth: Double
    public var bottomDockHeightRatio: Double

    public func panels(in dock: SideDock) -> [WorkbenchPanel] {
        WorkbenchPanel.allCases.filter { panel in
            let defaultDock: SideDock = [.repos, .tickets].contains(panel) ? .left : .right
            return (panelLocations?[panel.rawValue] ?? defaultDock) == dock
        }
    }

    public mutating func move(_ panel: WorkbenchPanel, to dock: SideDock) {
        var locations = panelLocations ?? [:]
        locations[panel.rawValue] = dock
        panelLocations = locations
        if dock == .left {
            activeLeftTab = panel
            isLeftDockCollapsed = false
            if activeRightTab == panel {
                activeRightTab = panels(in: .right).first ?? .changes
            }
        } else {
            activeRightTab = panel
            isRightDockCollapsed = false
            if activeLeftTab == panel {
                activeLeftTab = panels(in: .left).first ?? .repos
            }
        }
    }

    public init(
        activeCenterTab: CenterTab = .editor,
        activeLeftTab: LeftDockTab = .repos,
        activeRightTab: RightDockTab = .changes,
        isLeftDockCollapsed: Bool = false,
        isRightDockCollapsed: Bool = false,
        isBottomDockCollapsed: Bool = false,
        leftDockWidth: Double = 260,
        rightDockWidth: Double = 300,
        bottomDockHeightRatio: Double = 0.35
    ) {
        self.activeCenterTab = activeCenterTab
        self.activeLeftTab = activeLeftTab
        self.activeRightTab = activeRightTab
        self.isLeftDockCollapsed = isLeftDockCollapsed
        self.isRightDockCollapsed = isRightDockCollapsed
        self.isBottomDockCollapsed = isBottomDockCollapsed
        self.leftDockWidth = leftDockWidth
        self.rightDockWidth = rightDockWidth
        self.bottomDockHeightRatio = bottomDockHeightRatio
    }
}

public struct GitOperationResult: Sendable {
    public let success: Bool
    public let output: String
    public let error: String?
    public let partialSuccess: Bool

    public init(success: Bool, output: String = "", error: String? = nil, partialSuccess: Bool = false) {
        self.success = success
        self.output = output
        self.error = error
        self.partialSuccess = partialSuccess
    }
}

public struct GitStashItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String { ref }
    public let ref: String
    public let message: String
    public let date: String

    public init(ref: String, message: String, date: String = "") {
        self.ref = ref
        self.message = message
        self.date = date
    }
}

public struct GitWorktreeItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let head: String
    public let branch: String
    public let isMain: Bool

    public init(path: String, head: String, branch: String, isMain: Bool) {
        self.path = path
        self.head = head
        self.branch = branch
        self.isMain = isMain
    }
}

public struct BatchGitResult: Sendable {
    public let action: String
    public let results: [String: GitOperationResult]
    public let totalCount: Int
    public let successCount: Int
    public let failureCount: Int

    public init(action: String, results: [String: GitOperationResult]) {
        self.action = action
        self.results = results
        self.totalCount = results.count
        self.successCount = results.values.filter { $0.success }.count
        self.failureCount = results.values.filter { !$0.success }.count
    }
}

public struct AgentInfo: Codable, Identifiable, Hashable, Sendable {
    public var id: String { herdrPaneId ?? "\(pid)" }
    public let pid: Int
    public let tool: String
    public let status: String // "waiting" or "running"
    public let isWaitingForInput: Bool
    public let elapsed: String
    public let cpu: Double
    public let tty: String
    public let repoName: String?
    public let repoPath: String?
    public let command: String
    public let herdrPaneId: String?
    public let herdrWorkspaceId: String?
    public let herdrStatus: String?
    public let herdrTerminalTitle: String?
    public let isHerdrManaged: Bool

    public init(
        pid: Int,
        tool: String,
        status: String,
        isWaitingForInput: Bool,
        elapsed: String,
        cpu: Double = 0.0,
        tty: String = "",
        repoName: String? = nil,
        repoPath: String? = nil,
        command: String = "",
        herdrPaneId: String? = nil,
        herdrWorkspaceId: String? = nil,
        herdrStatus: String? = nil,
        herdrTerminalTitle: String? = nil,
        isHerdrManaged: Bool = false
    ) {
        self.pid = pid
        self.tool = tool
        self.status = status
        self.isWaitingForInput = isWaitingForInput
        self.elapsed = elapsed
        self.cpu = cpu
        self.tty = tty
        self.repoName = repoName
        self.repoPath = repoPath
        self.command = command
        self.herdrPaneId = herdrPaneId
        self.herdrWorkspaceId = herdrWorkspaceId
        self.herdrStatus = herdrStatus
        self.herdrTerminalTitle = herdrTerminalTitle
        self.isHerdrManaged = isHerdrManaged
    }

    enum CodingKeys: String, CodingKey {
        case pid, tool, status, isWaitingForInput, elapsed, cpu, tty, repoName, repoPath, command
        case herdrPaneId, herdrWorkspaceId, herdrStatus, herdrTerminalTitle, isHerdrManaged
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pid = try container.decode(Int.self, forKey: .pid)
        self.tool = try container.decode(String.self, forKey: .tool)
        self.status = try container.decode(String.self, forKey: .status)
        self.isWaitingForInput = try container.decode(Bool.self, forKey: .isWaitingForInput)
        self.elapsed = try container.decode(String.self, forKey: .elapsed)
        self.cpu = try container.decodeIfPresent(Double.self, forKey: .cpu) ?? 0.0
        self.tty = try container.decodeIfPresent(String.self, forKey: .tty) ?? ""
        self.repoName = try container.decodeIfPresent(String.self, forKey: .repoName)
        self.repoPath = try container.decodeIfPresent(String.self, forKey: .repoPath)
        self.command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
        self.herdrPaneId = try container.decodeIfPresent(String.self, forKey: .herdrPaneId)
        self.herdrWorkspaceId = try container.decodeIfPresent(String.self, forKey: .herdrWorkspaceId)
        self.herdrStatus = try container.decodeIfPresent(String.self, forKey: .herdrStatus)
        self.herdrTerminalTitle = try container.decodeIfPresent(String.self, forKey: .herdrTerminalTitle)
        self.isHerdrManaged = try container.decodeIfPresent(Bool.self, forKey: .isHerdrManaged) ?? false
    }
}

public struct TicketInfo: Codable, Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let summary: String
    public let status: String
    public let statusCategory: String // "todo", "in_progress", "done"
    public let priority: String // "High", "Medium", "Low", "None"
    public let isOpen: Bool
    public let localPath: String?
    public var notes: String

    public init(
        key: String,
        summary: String,
        status: String = "To Do",
        statusCategory: String = "todo",
        priority: String = "Medium",
        isOpen: Bool = true,
        localPath: String? = nil,
        notes: String = ""
    ) {
        self.key = key
        self.summary = summary
        self.status = status
        self.statusCategory = statusCategory
        self.priority = priority
        self.isOpen = isOpen
        self.localPath = localPath
        self.notes = notes
    }
}

public struct GraphifyNode: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let community: Int
    public let communityName: String
    public let fileType: String
    public let sourceFile: String?
    public let sourceLocation: String?

    public init(
        id: String,
        label: String,
        community: Int = 0,
        communityName: String = "Default",
        fileType: String = "unknown",
        sourceFile: String? = nil,
        sourceLocation: String? = nil
    ) {
        self.id = id
        self.label = label
        self.community = community
        self.communityName = communityName
        self.fileType = fileType
        self.sourceFile = sourceFile
        self.sourceLocation = sourceLocation
    }
}

public struct GraphifyLink: Codable, Hashable, Sendable {
    public let source: String
    public let target: String
    public let relation: String

    public init(source: String, target: String, relation: String = "") {
        self.source = source
        self.target = target
        self.relation = relation
    }
}

public struct GraphifyData: Codable, Sendable {
    public let nodes: [GraphifyNode]
    public let links: [GraphifyLink]
    public let communities: [Int]
    public let reportPath: String?
    public let htmlPath: String?

    public init(
        nodes: [GraphifyNode],
        links: [GraphifyLink],
        communities: [Int] = [],
        reportPath: String? = nil,
        htmlPath: String? = nil
    ) {
        self.nodes = nodes
        self.links = links
        self.communities = communities
        self.reportPath = reportPath
        self.htmlPath = htmlPath
    }
}
