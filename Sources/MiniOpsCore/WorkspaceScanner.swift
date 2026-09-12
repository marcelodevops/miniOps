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

    public static func detectRepoTags(url: URL) -> [String] {
        let name = url.lastPathComponent.lowercased()
        var tags = Set<String>()
        let nameTags: [(token: String, tag: String)] = [
            ("istio", "istio"), ("argocd", "argocd"), ("grafana", "grafana"),
            ("mcp", "mcp"), ("rke2", "k8s"), ("eks", "k8s"), ("kubernetes", "k8s"),
            ("k8s", "k8s"), ("cicd", "cicd"), ("github-actions", "cicd"),
            ("terraform", "terraform"), ("helm", "helm"), ("chart", "helm"),
            ("load-testing", "testing"), ("skills", "skills")
        ]
        for (token, tag) in nameTags {
            if name.contains(token) {
                tags.insert(tag)
            }
        }
        if let topFiles = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
            let lowerFiles = Set(topFiles.map { $0.lowercased() })
            if lowerFiles.contains(where: { $0.hasSuffix(".tf") }) {
                tags.insert("terraform")
            }
            if lowerFiles.contains("chart.yaml") {
                tags.insert("helm")
            }
            if lowerFiles.contains("dockerfile") || lowerFiles.contains(where: { $0.hasPrefix("dockerfile") }) {
                tags.insert("docker")
            }
            if lowerFiles.contains("package.swift") {
                tags.insert("swift")
            }
        }
        return tags.isEmpty ? ["other"] : tags.sorted()
    }

    private func makeRepoRecord(url: URL, group: String?) -> RepoInfo {
        let resolved = url.resolvingSymlinksInPath()
        let (branch, isDirty, ahead, behind, changes) = gitService.getRepoStatus(repoPath: resolved.path)
        let origin = gitService.getRemoteOriginType(repoPath: resolved.path)
        let tags = Self.detectRepoTags(url: resolved)
        let opState = gitService.getRepoOperationState(repoPath: resolved.path)
        return RepoInfo(
            name: resolved.lastPathComponent,
            path: resolved.path,
            groupName: group,
            branch: branch,
            isDirty: isDirty,
            ahead: ahead,
            behind: behind,
            changedFiles: changes,
            tags: tags,
            origin: origin,
            hasUpstream: opState.hasUpstream,
            stashCount: opState.stashCount,
            isMerging: opState.isMerging,
            isRebasing: opState.isRebasing,
            isCherryPicking: opState.isCherryPicking
        )
    }
}
