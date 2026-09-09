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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        process.environment = gitEnv()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            
            // Collect output concurrently to prevent pipe buffer deadlock
            var stdoutData = Data()
            var stderrData = Data()
            
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            
            process.waitUntilExit()
            group.wait()
            
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            var cleanStdout = stdout
            while cleanStdout.hasSuffix("\n") || cleanStdout.hasSuffix("\r") {
                cleanStdout.removeLast()
            }
            return (process.terminationStatus, cleanStdout, stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (-1, "", error.localizedDescription)
        }
    }

    public func getRepoStatus(repoPath: String) -> (branch: String, isDirty: Bool, ahead: Int, behind: Int, changes: [GitFileChange]) {
        // Branch
        let branchRes = runGit(args: ["rev-parse", "--abbrev-ref", "HEAD"], in: repoPath)
        let branch = branchRes.status == 0 && !branchRes.stdout.isEmpty ? branchRes.stdout : "(detached)"

        // Status porcelain
        let statusRes = runGit(args: ["status", "--porcelain=v1"], in: repoPath)
        let statusLines = statusRes.stdout.components(separatedBy: "\n").filter { !$0.isEmpty }
        let isDirty = !statusLines.isEmpty

        var changes: [GitFileChange] = []
        for line in statusLines {
            guard line.count >= 3 else { continue }
            let indexCode = line.prefix(1)
            let worktreeCode = line.dropFirst(1).prefix(1)
            let pathPart = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            
            // Extract clean path if renamed: "old -> new"
            let filePath: String
            if pathPart.contains(" -> ") {
                let parts = pathPart.components(separatedBy: " -> ")
                filePath = parts.last ?? pathPart
            } else {
                filePath = pathPart
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

    public func reconcile(repoPath: String, message: String = "reconciling latest changes", selectedPaths: [String]? = nil) -> GitOperationResult {
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
