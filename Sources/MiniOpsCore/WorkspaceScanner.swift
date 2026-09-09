import Foundation

public final class WorkspaceScanner: @unchecked Sendable {
    public static let shared = WorkspaceScanner()

    private let gitService: GitService
    private let skipDirs: Set<String> = [
        ".git", ".build", "node_modules", "DerivedData", "Pods", ".remember", ".codex"
    ]

    public init(gitService: GitService = .shared) {
        self.gitService = gitService
    }

    public func scan(rootPath: String) -> [RepoInfo] {
        let rootURL = URL(fileURLWithPath: (rootPath as NSString).expandingTildeInPath).standardized
        guard let items = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var repos: [RepoInfo] = []

        for itemURL in items.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            guard (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                continue
            }
            if skipDirs.contains(itemURL.lastPathComponent) {
                continue
            }

            let gitURL = itemURL.appendingPathComponent(".git")
            var isGitDir: ObjCBool = false
            let hasGit = FileManager.default.fileExists(atPath: gitURL.path, isDirectory: &isGitDir)

            if hasGit {
                // Direct repo
                let repo = makeRepoRecord(url: itemURL, group: nil)
                repos.append(repo)
            } else {
                // Potential grouping folder (e.g. MARVIN/, tools/, etc.)
                if let subItems = try? FileManager.default.contentsOfDirectory(at: itemURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                    for subURL in subItems.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                        guard (try? subURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                            continue
                        }
                        if skipDirs.contains(subURL.lastPathComponent) {
                            continue
                        }
                        let subGitURL = subURL.appendingPathComponent(".git")
                        if FileManager.default.fileExists(atPath: subGitURL.path) {
                            let subRepo = makeRepoRecord(url: subURL, group: itemURL.lastPathComponent)
                            repos.append(subRepo)
                        }
                    }
                }
            }
        }

        return repos
    }

    private func makeRepoRecord(url: URL, group: String?) -> RepoInfo {
        let (branch, isDirty, ahead, behind, changes) = gitService.getRepoStatus(repoPath: url.path)
        return RepoInfo(
            name: url.lastPathComponent,
            path: url.path,
            groupName: group,
            branch: branch,
            isDirty: isDirty,
            ahead: ahead,
            behind: behind,
            changedFiles: changes
        )
    }
}
