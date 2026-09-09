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
