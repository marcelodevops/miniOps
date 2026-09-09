import Foundation

public enum WorkspaceStatusType: Equatable, Sendable {
    case clean
    case dirtyRepos(Int)
    case agentWaiting(Int)
    case offline
}

public struct WorkspaceStatusSummary: Equatable, Sendable {
    public let type: WorkspaceStatusType
    public let title: String
    public let tooltip: String
    public let iconName: String

    public init(dirtyCount: Int, waitingAgentCount: Int = 0) {
        if waitingAgentCount > 0 {
            let plural = waitingAgentCount == 1 ? "" : "s"
            self.type = .agentWaiting(waitingAgentCount)
            self.title = "● \(waitingAgentCount)"
            self.tooltip = "miniOps: \(waitingAgentCount) agent\(plural) waiting for input"
            self.iconName = "exclamationmark.circle.fill"
        } else if dirtyCount > 0 {
            let plural = dirtyCount == 1 ? "" : "s"
            self.type = .dirtyRepos(dirtyCount)
            self.title = "● \(dirtyCount)"
            self.tooltip = "miniOps: \(dirtyCount) repo\(plural) with uncommitted changes"
            self.iconName = "circle.fill"
        } else {
            self.type = .clean
            self.title = "○"
            self.tooltip = "miniOps: all clean"
            self.iconName = "checkmark.circle.fill"
        }
    }
}
