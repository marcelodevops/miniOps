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

    public func scan(rootPath: String, customPaths: Set<String> = []) -> [RepoInfo] {
        let rootURL = URL(fileURLWithPath: (rootPath as NSString).expandingTildeInPath).resolvingSymlinksInPath()
        let items = (try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []

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

        // Add any custom imported paths that aren't already included
        for customPath in customPaths.sorted() {
            let expanded = URL(fileURLWithPath: (customPath as NSString).expandingTildeInPath).resolvingSymlinksInPath().path
            if !repos.contains(where: { $0.path == expanded }) {
                if let customRepo = inspectRepo(path: expanded, group: "Imported") {
                    repos.append(customRepo)
                }
            }
        }

        return repos
    }

    public func inspectRepo(path: String, group: String? = nil) -> RepoInfo? {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).resolvingSymlinksInPath()
        let gitURL = url.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitURL.path, isDirectory: &isDir) else {
            return nil
        }
        return makeRepoRecord(url: url, group: group)
    }

    private func makeRepoRecord(url: URL, group: String?) -> RepoInfo {
        let resolved = url.resolvingSymlinksInPath()
        let (branch, isDirty, ahead, behind, changes) = gitService.getRepoStatus(repoPath: resolved.path)
        return RepoInfo(
            name: resolved.lastPathComponent,
            path: resolved.path,
            groupName: group,
            branch: branch,
            isDirty: isDirty,
            ahead: ahead,
            behind: behind,
            changedFiles: changes
        )
    }
}
