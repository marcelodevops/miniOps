import Foundation

public final class GitService: @unchecked Sendable {
    public static let shared = GitService()

    private let lockManager: RepoLockManager

    public init(lockManager: RepoLockManager = .shared) {
        self.lockManager = lockManager
    }

    private func gitEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_ASKPASS"] = "true"
        return env
    }

    private func runGit(args: [String], in repoPath: String, timeout: TimeInterval = 60) -> (status: Int32, stdout: String, stderr: String) {
        let result = ProcessRunner.run(
            executable: "/usr/bin/git",
            arguments: args,
            currentDirectory: repoPath,
            environment: gitEnv(),
            timeout: timeout
        )
        var cleanStdout = result.stdout
        while cleanStdout.hasSuffix("\n") || cleanStdout.hasSuffix("\r") {
            cleanStdout.removeLast()
        }
        return (result.status, cleanStdout, result.stderr)
    }

    public func getRepoStatus(repoPath: String) -> (branch: String, isDirty: Bool, ahead: Int, behind: Int, changes: [GitFileChange]) {
        // Branch
        let branchRes = runGit(args: ["rev-parse", "--abbrev-ref", "HEAD"], in: repoPath)
        let branch = branchRes.status == 0 && !branchRes.stdout.isEmpty ? branchRes.stdout : "(detached)"

        // Status porcelain
        let statusRes = runGit(args: ["status", "--porcelain=v1", "-z"], in: repoPath)
        let records = statusRes.stdout.components(separatedBy: "\0")
        let isDirty = records.contains { !$0.isEmpty }

        var changes: [GitFileChange] = []
        var recordIndex = 0
        while recordIndex < records.count {
            let line = records[recordIndex]
            recordIndex += 1
            guard line.count >= 3 else { continue }
            let indexCode = line.prefix(1)
            let worktreeCode = line.dropFirst(1).prefix(1)
            let filePath = String(line.dropFirst(3))
            // In -z mode the destination precedes the separate source record.
            if indexCode == "R" || indexCode == "C" || worktreeCode == "R" || worktreeCode == "C" {
                recordIndex += 1
            }

            let isUntracked = (indexCode == "?" && worktreeCode == "?")
            let isStaged = (indexCode != " " && indexCode != "?")
            let code = "\(indexCode)\(worktreeCode)".trimmingCharacters(in: .whitespaces)

            changes.append(GitFileChange(
                path: filePath,
                statusLetter: code,
                isStaged: isStaged,
                isUntracked: isUntracked
            ))
        }

        // Ahead / Behind
        var ahead = 0
        var behind = 0
        let upstreamCheck = runGit(args: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], in: repoPath)
        if upstreamCheck.status == 0 && !upstreamCheck.stdout.isEmpty {
            let countsRes = runGit(args: ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"], in: repoPath)
            if countsRes.status == 0 {
                let parts = countsRes.stdout.split(whereSeparator: { $0.isWhitespace })
                if parts.count >= 2, let b = Int(parts[0]), let a = Int(parts[1]) {
                    behind = b
                    ahead = a
                }
            }
        }

        return (branch, isDirty, ahead, behind, changes)
    }

    public func getDiff(repoPath: String, filePath: String, cached: Bool = false) -> String {
        // Check if file is untracked
        let fullURL = URL(fileURLWithPath: repoPath).appendingPathComponent(filePath)
        var isUntracked = false
        let statusRes = runGit(args: ["--literal-pathspecs", "status", "--porcelain=v1", "--", filePath], in: repoPath)
        if statusRes.stdout.starts(with: "??") {
            isUntracked = true
        }

        if isUntracked {
            // For untracked files, show added content
            if let content = try? String(contentsOf: fullURL, encoding: .utf8) {
                let lines = content.components(separatedBy: "\n")
                var diff = "diff --git a/\(filePath) b/\(filePath)\nnew file mode 100644\n--- /dev/null\n+++ b/\(filePath)\n@@ -0,0 +1,\(lines.count) @@\n"
                for line in lines {
                    diff += "+\(line)\n"
                }
                return diff
            }
            return "(Untracked file cannot be read as text)"
        }

        var args = ["--literal-pathspecs", "diff"]
        if cached {
            args.append("--cached")
        }
        args.append("--")
        args.append(filePath)

        let diffRes = runGit(args: args, in: repoPath)
        return diffRes.stdout.isEmpty ? (diffRes.stderr.isEmpty ? "No differences" : diffRes.stderr) : diffRes.stdout
    }

    public func validatePaths(repoPath: String, paths: [String]) throws -> [String] {
        guard !paths.isEmpty else {
            throw NSError(domain: "GitService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No files selected to commit"])
        }

        let repoURL = URL(fileURLWithPath: repoPath).standardized
        var validated: [String] = []

        for p in paths {
            let clean = NSString(string: p).standardizingPath
            if clean.isEmpty || clean == "." || clean.hasPrefix("/") || clean.hasPrefix("../") || clean.contains("/../") {
                throw NSError(domain: "GitService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid file path: \(p)"])
            }
            let fileURL = repoURL.appendingPathComponent(clean).standardized
            guard fileURL.path.hasPrefix(repoURL.path) else {
                throw NSError(domain: "GitService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Path escapes repository: \(p)"])
            }
            validated.append(clean)
        }
        return validated
    }

    public func selectiveCommit(repoPath: String, message: String, selectedPaths: [String]) -> GitOperationResult {
        let trimmedMsg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMsg.isEmpty else {
            return GitOperationResult(success: false, error: "Commit message cannot be empty")
        }
        guard trimmedMsg.count <= 2000 else {
            return GitOperationResult(success: false, error: "Commit message too long (max 2000 characters)")
        }

        do {
            return try lockManager.withRepoLock(repoPath: repoPath, action: "commit") {
                let paths: [String]
                do {
                    paths = try validatePaths(repoPath: repoPath, paths: selectedPaths)
                } catch {
                    return GitOperationResult(success: false, error: error.localizedDescription)
                }

                // Stage ONLY specified paths with literal pathspecs
                var addArgs = ["--literal-pathspecs", "add", "--"]
                addArgs.append(contentsOf: paths)
                let addRes = runGit(args: addArgs, in: repoPath)
                if addRes.status != 0 {
                    let err = addRes.stderr.isEmpty ? addRes.stdout : addRes.stderr
                    return GitOperationResult(success: false, error: "Git add failed: \(err)")
                }

                // Commit ONLY specified paths with literal pathspecs to preserve unrelated staging
                var commitArgs = ["--literal-pathspecs", "commit", "-m", trimmedMsg, "--only", "--"]
                commitArgs.append(contentsOf: paths)
                let commitRes = runGit(args: commitArgs, in: repoPath)
                if commitRes.status != 0 {
                    let err = commitRes.stderr.isEmpty ? commitRes.stdout : commitRes.stderr
                    return GitOperationResult(success: false, error: "Git commit failed: \(err)")
                }

                return GitOperationResult(success: true, output: commitRes.stdout)
            }
        } catch {
            return GitOperationResult(success: false, error: error.localizedDescription)
        }
    }

    public func commitAll(repoPath: String, message: String) -> GitOperationResult {
        let trimmedMsg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMsg.isEmpty else {
            return GitOperationResult(success: false, error: "Commit message cannot be empty")
        }

        do {
            return try lockManager.withRepoLock(repoPath: repoPath, action: "commitAll") {
                let addRes = runGit(args: ["add", "-A"], in: repoPath)
                if addRes.status != 0 {
                    return GitOperationResult(success: false, error: "Git add -A failed: \(addRes.stderr)")
                }
                let commitRes = runGit(args: ["commit", "-m", trimmedMsg], in: repoPath)
                if commitRes.status != 0 {
                    return GitOperationResult(success: false, error: "Git commit failed: \(commitRes.stderr)")
                }
                return GitOperationResult(success: true, output: commitRes.stdout)
            }
        } catch {
            return GitOperationResult(success: false, error: error.localizedDescription)
        }
    }

    public func push(repoPath: String) -> GitOperationResult {
        do {
            return try lockManager.withRepoLock(repoPath: repoPath, action: "push") {
                // Check branch
                let branchRes = runGit(args: ["branch", "--show-current"], in: repoPath)
                let branch = branchRes.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                guard branchRes.status == 0, !branch.isEmpty else {
                    return GitOperationResult(success: false, error: "Cannot push a detached HEAD")
                }

                let upstreamRes = runGit(args: ["rev-parse", "--abbrev-ref", "@{upstream}"], in: repoPath)
                let pushArgs = (upstreamRes.status == 0) ? ["push"] : ["push", "-u", "origin", branch]

                let pushRes = runGit(args: pushArgs, in: repoPath, timeout: 120)
                if pushRes.status != 0 {
                    let err = pushRes.stderr.isEmpty ? pushRes.stdout : pushRes.stderr
                    return GitOperationResult(success: false, error: "Git push failed: \(err)")
                }
                return GitOperationResult(success: true, output: pushRes.stdout.isEmpty ? "Everything up-to-date" : pushRes.stdout)
            }
        } catch {
            return GitOperationResult(success: false, error: error.localizedDescription)
        }
    }

    /// Stage every change, commit it with a custom message and push the current branch in one step.
    /// Mirrors the `xgit` shell workflow: `git add -A` + `git commit -m` + `git push` (with upstream set on first push).
    public func addCommitPush(repoPath: String, message: String) -> GitOperationResult {
        let trimmedMsg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMsg.isEmpty else {
            return GitOperationResult(success: false, error: "Commit message cannot be empty")
        }
        guard trimmedMsg.count <= 2000 else {
            return GitOperationResult(success: false, error: "Commit message too long (max 2000 characters)")
        }

        do {
            return try lockManager.withRepoLock(repoPath: repoPath, action: "addCommitPush") {
                let addRes = runGit(args: ["add", "-A"], in: repoPath)
                if addRes.status != 0 {
                    let err = addRes.stderr.isEmpty ? addRes.stdout : addRes.stderr
                    return GitOperationResult(success: false, error: "Git add -A failed: \(err)")
                }

                // Same guard as `git diff --cached --quiet` in xgit: exit 0 means nothing is staged.
                let stagedRes = runGit(args: ["diff", "--cached", "--quiet"], in: repoPath)
                if stagedRes.status == 0 {
                    return GitOperationResult(success: false, error: "Nothing to commit")
                }

                let commitRes = runGit(args: ["commit", "-m", trimmedMsg], in: repoPath)
                if commitRes.status != 0 {
                    let err = commitRes.stderr.isEmpty ? commitRes.stdout : commitRes.stderr
                    return GitOperationResult(success: false, error: "Git commit failed: \(err)")
                }

                let pushRes = push(repoPath: repoPath)
                if !pushRes.success {
                    return GitOperationResult(
                        success: false,
                        output: "Commit created locally",
                        error: "commit created, but push failed: \(pushRes.error ?? "unknown error")",
                        partialSuccess: true
                    )
                }

                return GitOperationResult(success: true, output: "Committed and pushed: \(trimmedMsg)")
            }
        } catch {
            return GitOperationResult(success: false, error: error.localizedDescription)
        }
    }

    public func reconcile(repoPath: String, message: String = "reconciling latest changes", selectedPaths: [String]? = nil) -> GitOperationResult {
        if let selectedPaths, selectedPaths.isEmpty {
            return GitOperationResult(success: false, error: "No files selected to reconcile")
        }
        do {
            return try lockManager.withRepoLock(repoPath: repoPath, action: "reconcile") {
                let (_, isDirty, _, _, _) = getRepoStatus(repoPath: repoPath)
                var commitCreated = false

                if isDirty {
                    let commitRes: GitOperationResult
                    if let selectedPaths = selectedPaths, !selectedPaths.isEmpty {
                        commitRes = selectiveCommit(repoPath: repoPath, message: message, selectedPaths: selectedPaths)
                    } else {
                        commitRes = commitAll(repoPath: repoPath, message: message)
                    }

                    if !commitRes.success {
                        return commitRes
                    }
                    commitCreated = true
                }

                // Now push
                let pushRes = push(repoPath: repoPath)
                if !pushRes.success {
                    if commitCreated {
                        return GitOperationResult(
                            success: false,
                            output: "Commit created locally",
                            error: "commit created, but push failed: \(pushRes.error ?? "unknown error")",
                            partialSuccess: true
                        )
                    }
                    return pushRes
                }

                return GitOperationResult(
                    success: true,
                    output: commitCreated ? "Reconciled: committed and pushed." : "Already clean and up-to-date."
                )
            }
        } catch {
            return GitOperationResult(success: false, error: error.localizedDescription)
        }
    }
}

// MARK: - Extended Git Operations
extension GitService {
    private static let branchRegex = try! NSRegularExpression(pattern: "^[A-Za-z0-9][A-Za-z0-9._/-]*$")
    private static let stashRefRegex = try! NSRegularExpression(pattern: "^stash@\\{[0-9]+\\}$")

    public func fetch(repoPath: String) -> GitOperationResult {
        do {
            return try lockManager.withRepoLock(repoPath: repoPath, action: "fetch") {
                let res = runGit(args: ["fetch", "--all", "--prune"], in: repoPath, timeout: 60)
                if res.status != 0 {
                    let err = res.stderr.isEmpty ? res.stdout : res.stderr
                    return GitOperationResult(success: false, error: "Git fetch failed: \(err)")
                }
                return GitOperationResult(success: true, output: res.stdout.isEmpty ? "Fetch completed." : res.stdout)
            }
        } catch {
            return GitOperationResult(success: false, error: error.localizedDescription)
        }
    }

    public func pull(repoPath: String) -> GitOperationResult {
        do {
            return try lockManager.withRepoLock(repoPath: repoPath, action: "pull") {
                let res = runGit(args: ["pull", "--ff-only"], in: repoPath, timeout: 60)
                if res.status != 0 {
                    let err = res.stderr.isEmpty ? res.stdout : res.stderr
                    return GitOperationResult(success: false, error: "Git pull failed: \(err)")
                }
                return GitOperationResult(success: true, output: res.stdout.isEmpty ? "Already up to date." : res.stdout)
            }
        } catch {
            return GitOperationResult(success: false, error: error.localizedDescription)
        }
    }

    public func listBranches(repoPath: String) -> [String] {
        let res = runGit(args: ["branch", "--list", "--format=%(refname:short)"], in: repoPath)
        guard res.status == 0 else { return [] }
        return res.stdout.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public func checkout(repoPath: String, branch: String) -> GitOperationResult {
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        guard Self.branchRegex.firstMatch(in: trimmed, range: range) != nil else {
            return GitOperationResult(success: false, error: "Invalid branch name: \(branch)")
        }

        do {
            return try lockManager.withRepoLock(repoPath: repoPath, action: "checkout") {
                let res = runGit(args: ["checkout", trimmed], in: repoPath)
                if res.status != 0 {
                    let err = res.stderr.isEmpty ? res.stdout : res.stderr
                    return GitOperationResult(success: false, error: "Git checkout failed: \(err)")
                }
                return GitOperationResult(success: true, output: res.stdout)
            }
        } catch {
            return GitOperationResult(success: false, error: error.localizedDescription)
        }
    }

    public func createBranch(repoPath: String, branchName: String, startPoint: String? = nil) -> GitOperationResult {
        let trimmed = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        guard Self.branchRegex.firstMatch(in: trimmed, range: range) != nil else {
            return GitOperationResult(success: false, error: "Invalid branch name: \(branchName)")
        }

        var args = ["checkout", "-b", trimmed]
        if let start = startPoint?.trimmingCharacters(in: .whitespacesAndNewlines), !start.isEmpty {
            let startRange = NSRange(location: 0, length: start.utf16.count)
            guard Self.branchRegex.firstMatch(in: start, range: startRange) != nil else {
                return GitOperationResult(success: false, error: "Invalid start point branch name: \(start)")
            }
            args.append(start)
        }

        do {
            return try lockManager.withRepoLock(repoPath: repoPath, action: "createBranch") {
                let res = runGit(args: args, in: repoPath)
                if res.status != 0 {
                    let err = res.stderr.isEmpty ? res.stdout : res.stderr
                    return GitOperationResult(success: false, error: "Git create branch failed: \(err)")
                }
                return GitOperationResult(success: true, output: res.stdout)
            }
        } catch {
            return GitOperationResult(success: false, error: error.localizedDescription)
        }
    }

    public func listStashes(repoPath: String) -> [GitStashItem] {
        let res = runGit(args: ["stash", "list", "--format=%gd%x1f%gs%x1f%ci"], in: repoPath)
        guard res.status == 0 else { return [] }
        var items: [GitStashItem] = []
        for line in res.stdout.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\u{1f}")
            if parts.count >= 2 {
                let ref = parts[0].trimmingCharacters(in: .whitespaces)
                let msg = parts[1].trimmingCharacters(in: .whitespaces)
                let date = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
                let range = NSRange(location: 0, length: ref.utf16.count)
                if Self.stashRefRegex.firstMatch(in: ref, range: range) != nil {
                    items.append(GitStashItem(ref: ref, message: msg, date: date))
                }
            }
        }
        return items
    }

    public func stash(repoPath: String, message: String = "") -> GitOperationResult {
        do {
            return try lockManager.withRepoLock(repoPath: repoPath, action: "stash") {
                var args = ["stash", "push", "-u"]
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    args.append(contentsOf: ["-m", trimmed])
                }
                let res = runGit(args: args, in: repoPath)
                if res.status != 0 {
                    let err = res.stderr.isEmpty ? res.stdout : res.stderr
                    return GitOperationResult(success: false, error: "Git stash failed: \(err)")
                }
                return GitOperationResult(success: true, output: res.stdout)
            }
        } catch {
            return GitOperationResult(success: false, error: error.localizedDescription)
        }
    }

    public func showStash(repoPath: String, stashRef: String) -> String {
        let trimmed = stashRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        guard Self.stashRefRegex.firstMatch(in: trimmed, range: range) != nil else {
            return "Invalid stash reference: \(stashRef)"
        }
        let res = runGit(args: ["stash", "show", "--include-untracked", "--patch", "--no-color", trimmed], in: repoPath)
        return res.stdout.isEmpty ? (res.stderr.isEmpty ? "No differences" : res.stderr) : res.stdout
    }

    public func popStash(repoPath: String, stashRef: String = "stash@{0}") -> GitOperationResult {
        let trimmed = stashRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        guard Self.stashRefRegex.firstMatch(in: trimmed, range: range) != nil else {
            return GitOperationResult(success: false, error: "Invalid stash reference: \(stashRef)")
        }

        do {
            return try lockManager.withRepoLock(repoPath: repoPath, action: "popStash") {
                // Check if repo has uncommitted changes
                let (_, isDirty, _, _, _) = getRepoStatus(repoPath: repoPath)
                if isDirty {
                    return GitOperationResult(success: false, error: "Stash pop requires a clean working tree to prevent conflicts")
                }

                let res = runGit(args: ["stash", "pop", trimmed], in: repoPath)
                if res.status != 0 {
                    let err = res.stderr.isEmpty ? res.stdout : res.stderr
                    return GitOperationResult(success: false, error: "Git stash pop failed: \(err)")
                }
                return GitOperationResult(success: true, output: res.stdout)
            }
        } catch {
            return GitOperationResult(success: false, error: error.localizedDescription)
        }
    }

    public func listWorktrees(repoPath: String) -> [GitWorktreeItem] {
        let res = runGit(args: ["worktree", "list", "--porcelain"], in: repoPath)
        guard res.status == 0 else { return [] }

        var items: [GitWorktreeItem] = []
        var currentPath = ""
        var currentHead = ""
        var currentBranch = ""
        let targetNorm = URL(fileURLWithPath: repoPath).resolvingSymlinksInPath().standardized.path

        for line in res.stdout.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !currentPath.isEmpty {
                    let isMain = URL(fileURLWithPath: currentPath).resolvingSymlinksInPath().standardized.path == targetNorm
                    items.append(GitWorktreeItem(path: currentPath, head: currentHead, branch: currentBranch, isMain: isMain))
                    currentPath = ""
                    currentHead = ""
                    currentBranch = ""
                }
                continue
            }

            if trimmed.hasPrefix("worktree ") {
                currentPath = String(trimmed.dropFirst("worktree ".count)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("HEAD ") {
                currentHead = String(trimmed.dropFirst("HEAD ".count)).trimmingCharacters(in: .whitespaces).prefix(7).description
            } else if trimmed.hasPrefix("branch ") {
                let ref = String(trimmed.dropFirst("branch ".count)).trimmingCharacters(in: .whitespaces)
                currentBranch = ref.replacingOccurrences(of: "refs/heads/", with: "")
            }
        }

        if !currentPath.isEmpty {
            let isMain = URL(fileURLWithPath: currentPath).resolvingSymlinksInPath().standardized.path == targetNorm
            items.append(GitWorktreeItem(path: currentPath, head: currentHead, branch: currentBranch, isMain: isMain))
        }

        return items
    }

    public func addWorktree(repoPath: String, worktreePath: String, branch: String? = nil, newBranch: String? = nil) -> GitOperationResult {
        let cleanPath = (worktreePath as NSString).expandingTildeInPath
        guard !cleanPath.trimmingCharacters(in: .whitespaces).isEmpty else {
            return GitOperationResult(success: false, error: "Missing worktree destination path")
        }

        var args = ["worktree", "add"]
        if let nb = newBranch?.trimmingCharacters(in: .whitespaces), !nb.isEmpty {
            let range = NSRange(location: 0, length: nb.utf16.count)
            guard Self.branchRegex.firstMatch(in: nb, range: range) != nil else {
                return GitOperationResult(success: false, error: "Invalid new branch name: \(nb)")
            }
            args.append(contentsOf: ["-b", nb, cleanPath])
            if let b = branch?.trimmingCharacters(in: .whitespaces), !b.isEmpty {
                args.append(b)
            }
        } else if let b = branch?.trimmingCharacters(in: .whitespaces), !b.isEmpty {
            args.append(contentsOf: [cleanPath, b])
        } else {
            args.append(cleanPath)
        }

        do {
            return try lockManager.withRepoLock(repoPath: repoPath, action: "addWorktree") {
                let res = runGit(args: args, in: repoPath)
                if res.status != 0 {
                    let err = res.stderr.isEmpty ? res.stdout : res.stderr
                    return GitOperationResult(success: false, error: "Git worktree add failed: \(err)")
                }
                return GitOperationResult(success: true, output: res.stdout)
            }
        } catch {
            return GitOperationResult(success: false, error: error.localizedDescription)
        }
    }

    public func removeWorktree(repoPath: String, worktreePath: String, force: Bool = false) -> GitOperationResult {
        let cleanPath = (worktreePath as NSString).expandingTildeInPath
        var args = ["worktree", "remove"]
        if force {
            args.append("--force")
        }
        args.append(cleanPath)

        do {
            return try lockManager.withRepoLock(repoPath: repoPath, action: "removeWorktree") {
                let res = runGit(args: args, in: repoPath)
                if res.status != 0 {
                    let err = res.stderr.isEmpty ? res.stdout : res.stderr
                    return GitOperationResult(success: false, error: "Git worktree remove failed: \(err)")
                }
                return GitOperationResult(success: true, output: res.stdout)
            }
        } catch {
            return GitOperationResult(success: false, error: error.localizedDescription)
        }
    }

    public func batchGit(action: String, repoPaths: [String]) -> BatchGitResult {
        var results: [String: GitOperationResult] = [:]
        for path in repoPaths {
            switch action {
            case "fetch":
                results[path] = fetch(repoPath: path)
            case "pull":
                let (_, isDirty, _, _, _) = getRepoStatus(repoPath: path)
                if isDirty {
                    results[path] = GitOperationResult(success: false, error: "Skipped: repository has uncommitted changes")
                } else {
                    results[path] = pull(repoPath: path)
                }
            case "reconcile":
                results[path] = reconcile(repoPath: path, message: "reconciling latest changes")
            case "stash":
                let (_, isDirty, _, _, _) = getRepoStatus(repoPath: path)
                if isDirty {
                    results[path] = stash(repoPath: path, message: "miniOps batch stash")
                } else {
                    results[path] = GitOperationResult(success: true, output: "Clean, no stash needed")
                }
            default:
                results[path] = GitOperationResult(success: false, error: "Unknown batch action: \(action)")
            }
        }
        return BatchGitResult(action: action, results: results)
    }
}
