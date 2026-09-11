import Foundation

public extension Notification.Name {
    static let miniOpsOpenWorkspace = Notification.Name("miniOpsOpenWorkspace")
    static let miniOpsSaveFile = Notification.Name("miniOpsSaveFile")
    static let miniOpsToggleGitInspector = Notification.Name("miniOpsToggleGitInspector")
    static let miniOpsReconcile = Notification.Name("miniOpsReconcile")
    static let miniOpsRefreshGitStatus = Notification.Name("miniOpsRefreshGitStatus")
    static let miniOpsToggleTerminal = Notification.Name("miniOpsToggleTerminal")
    static let miniOpsToggleEditor = Notification.Name("miniOpsToggleEditor")
    static let miniOpsCloneRepo = Notification.Name("miniOpsCloneRepo")
    static let miniOpsOpenSettings = Notification.Name("miniOpsOpenSettings")
    static let miniOpsFetch = Notification.Name("miniOpsFetch")
    static let miniOpsPull = Notification.Name("miniOpsPull")
    static let miniOpsPush = Notification.Name("miniOpsPush")
    static let miniOpsAddCommitPush = Notification.Name("miniOpsAddCommitPush")
}
