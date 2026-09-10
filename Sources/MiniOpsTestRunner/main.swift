import Foundation
import MiniOpsCore

var passedCount = 0
var failedCount = 0

func assert(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("  ❌ Assertion Failed [\(line)]: \(message)")
        failedCount += 1
    } else {
        passedCount += 1
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if a != b {
        print("  ❌ Assertion Failed [\(line)]: expected '\(b)', got '\(a)'. \(message)")
        failedCount += 1
    } else {
        passedCount += 1
    }
}

func runGit(args: [String], in dir: String) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = URL(fileURLWithPath: dir)
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try? process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func setupTempRepo() -> (tempDir: URL, repoURL: URL) {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let repoURL = tempDir.appendingPathComponent("test-repo")
    try! FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

    _ = runGit(args: ["init", "-b", "main"], in: repoURL.path)
    _ = runGit(args: ["config", "user.name", "miniOps Test"], in: repoURL.path)
    _ = runGit(args: ["config", "user.email", "test@example.com"], in: repoURL.path)
    _ = runGit(args: ["config", "commit.gpgsign", "false"], in: repoURL.path)
    return (tempDir, repoURL)
}

print("==================================================")
print("Running miniOps Git Safety & Correctness Tests")
print("==================================================")

// Test 0: Process Runner Enforces Deadlines
print("Test 0: Process Runner Enforces Deadlines")
do {
    let result = ProcessRunner.run(
        executable: "/bin/sh",
        arguments: ["-c", "sleep 2"],
        currentDirectory: NSTemporaryDirectory(),
        timeout: 0.1
    )
    assert(result.timedOut, "A process exceeding its deadline must be marked timed out")
    assert(result.status != 0, "A timed-out process must not report success")
    assert(result.stderr.contains("timed out"), "Timeout diagnostics must be returned")
}

// Test 1: Selective Commit Stages Only Specified Paths
print("Test 1: Selective Commit Stages Only Specified Paths")
do {
    let (tempDir, repoURL) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileA = repoURL.appendingPathComponent("a.txt")
    let fileB = repoURL.appendingPathComponent("b.txt")
    try! "content A".write(to: fileA, atomically: true, encoding: .utf8)
    try! "content B".write(to: fileB, atomically: true, encoding: .utf8)

    let gitService = GitService.shared
    let result = gitService.selectiveCommit(repoPath: repoURL.path, message: "Commit only a", selectedPaths: ["a.txt"])
    assert(result.success, "Commit should succeed: \(result.error ?? "")")

    let committed = runGit(args: ["show", "--pretty=", "--name-only", "HEAD"], in: repoURL.path)
    assert(committed.contains("a.txt"), "Committed files must contain a.txt")
    assert(!committed.contains("b.txt"), "Committed files must NOT contain b.txt")

    let status = runGit(args: ["status", "--porcelain"], in: repoURL.path)
    assert(status.contains("?? b.txt"), "b.txt must remain untracked")
}

// Test 2: Selective Commit Preserves Excluded Staging
print("Test 2: Selective Commit Preserves Excluded Staging")
do {
    let (tempDir, repoURL) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let excludedFile = repoURL.appendingPathComponent("excluded.txt")
    let selectedFile = repoURL.appendingPathComponent("selected.txt")
    try! "excluded content".write(to: excludedFile, atomically: true, encoding: .utf8)
    _ = runGit(args: ["add", "excluded.txt"], in: repoURL.path)

    try! "selected content".write(to: selectedFile, atomically: true, encoding: .utf8)

    let gitService = GitService.shared
    let result = gitService.selectiveCommit(repoPath: repoURL.path, message: "Commit selected only", selectedPaths: ["selected.txt"])
    assert(result.success, "Commit should succeed: \(result.error ?? "")")

    let committed = runGit(args: ["show", "--pretty=", "--name-only", "HEAD"], in: repoURL.path)
    assertEqual(committed, "selected.txt", "Only selected.txt should be in the commit")

    let staged = runGit(args: ["diff", "--cached", "--name-only"], in: repoURL.path)
    assertEqual(staged, "excluded.txt", "Excluded staged file must remain staged!")
}

// Test 3: Selective Commit Treats Wildcards And Spaces Literally
print("Test 3: Selective Commit Treats Wildcards And Spaces Literally")
do {
    let (tempDir, repoURL) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let wildcardFile = repoURL.appendingPathComponent("*.txt")
    let spacedFile = repoURL.appendingPathComponent("file with spaces.txt")
    let otherFile = repoURL.appendingPathComponent("other.txt")

    try! "literal wildcard".write(to: wildcardFile, atomically: true, encoding: .utf8)
    try! "spaced content".write(to: spacedFile, atomically: true, encoding: .utf8)
    try! "other content".write(to: otherFile, atomically: true, encoding: .utf8)

    let gitService = GitService.shared
    let result = gitService.selectiveCommit(repoPath: repoURL.path, message: "Commit literal files", selectedPaths: ["*.txt", "file with spaces.txt"])
    assert(result.success, "Commit should succeed: \(result.error ?? "")")

    let committed = runGit(args: ["show", "--pretty=", "--name-only", "HEAD"], in: repoURL.path)
    assert(committed.contains("*.txt"), "Commit must contain *.txt literally")
    assert(committed.contains("file with spaces.txt"), "Commit must contain file with spaces.txt")
    assert(!committed.contains("other.txt"), "Commit must NOT contain other.txt")
}

// Test 4: Selective Commit Rejects Empty And Traversal Paths
print("Test 4: Selective Commit Rejects Empty And Traversal Paths")
do {
    let (tempDir, repoURL) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let gitService = GitService.shared
    let emptyRes = gitService.selectiveCommit(repoPath: repoURL.path, message: "Empty selection", selectedPaths: [])
    assert(!emptyRes.success, "Empty selection should fail")
    assert(emptyRes.error?.contains("No files selected") == true, "Expected 'No files selected' error")

    let traversalRes = gitService.selectiveCommit(repoPath: repoURL.path, message: "Traversal", selectedPaths: ["../escape.txt"])
    assert(!traversalRes.success, "Traversal should fail")
}

// Test 5: Repo Lock Serializes Concurrent Mutations
print("Test 5: Repo Lock Serializes Concurrent Mutations")
do {
    let (tempDir, repoURL) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let lockManager = RepoLockManager()
    let pathA = repoURL.path
    let pathB = tempDir.appendingPathComponent("other-repo").path

    let semEntered = DispatchSemaphore(value: 0)
    let semRelease = DispatchSemaphore(value: 0)

    var threadBBlocked = false
    var threadBAllowedOther = false

    let queueA = DispatchQueue(label: "threadA")
    let queueB = DispatchQueue(label: "threadB")

    queueA.async {
        do {
            _ = try lockManager.withRepoLock(repoPath: pathA, action: "slowOperation") {
                semEntered.signal()
                _ = semRelease.wait(timeout: .now() + 2.0)
            }
        } catch {
            print("Thread A error: \(error)")
        }
    }

    _ = semEntered.wait(timeout: .now() + 2.0)

    queueB.sync {
        do {
            _ = try lockManager.withRepoLock(repoPath: pathA, action: "fastOperation") {}
        } catch RepoLockError.repositoryBusy {
            threadBBlocked = true
        } catch {
            print("Unexpected error on same repo: \(error)")
        }

        do {
            _ = try lockManager.withRepoLock(repoPath: pathB, action: "otherOperation") {
                threadBAllowedOther = true
            }
        } catch {
            print("Unexpected error on other repo: \(error)")
        }
    }

    assert(threadBBlocked, "Thread B must be blocked on same repo")
    assert(threadBAllowedOther, "Thread B must be allowed on different repo")

    semRelease.signal()
    Thread.sleep(forTimeInterval: 0.1)

    var subsequentSuccess = false
    queueB.sync {
        do {
            _ = try lockManager.withRepoLock(repoPath: pathA, action: "subsequentOperation") {
                subsequentSuccess = true
            }
        } catch {
            print("Subsequent error: \(error)")
        }
    }
    assert(subsequentSuccess, "Lock must be released and available for next operation")
}

// Test 6: Cancellation Does Not Release Running Operation
print("Test 6: Cancellation Does Not Release Running Operation")
do {
    let (tempDir, repoURL) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let lockManager = RepoLockManager()
    let pathA = repoURL.path

    let key = try! lockManager.tryAcquire(repoPath: pathA, action: "runningOp")
    assert(lockManager.isBusy(repoPath: pathA), "Lock must be busy")

    let (cancelled, _) = lockManager.cancelOperation(repoPath: pathA)
    assert(!cancelled, "Operation should not be cancelled if running")
    assert(lockManager.isBusy(repoPath: pathA), "Lock must not be released merely on cancel request")

    lockManager.release(repoKey: key)
    assert(!lockManager.isBusy(repoPath: pathA), "Lock is released only when operation terminates")
}

// Test 7: Workspace Scanner Grouping Folder Discovery
print("Test 7: Workspace Scanner Grouping Folder Discovery")
do {
    let (tempDir, _) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let root = tempDir.appendingPathComponent("scanner-root")
    let directRepo = root.appendingPathComponent("direct-repo")
    let groupDir = root.appendingPathComponent("GROUP-A")
    let nested1 = groupDir.appendingPathComponent("nested-1")
    let nested2 = groupDir.appendingPathComponent("nested-2")

    for d in [directRepo, nested1, nested2] {
        try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        _ = runGit(args: ["init", "-b", "main"], in: d.path)
    }

    let scanner = WorkspaceScanner.shared
    let repos = scanner.scan(rootPath: root.path)

    assertEqual(repos.count, 3, "Scanner must find exactly 3 repositories")
    let direct = repos.first { $0.name == "direct-repo" }
    assert(direct != nil, "Direct repo found")
    assert(direct?.groupName == nil, "Direct repo has no group")

    let n1 = repos.first { $0.name == "nested-1" }
    assert(n1 != nil, "Nested repo 1 found")
    assertEqual(n1?.groupName, "GROUP-A", "Nested repo 1 belongs to GROUP-A")

    let n2 = repos.first { $0.name == "nested-2" }
    assert(n2 != nil, "Nested repo 2 found")
    assertEqual(n2?.groupName, "GROUP-A", "Nested repo 2 belongs to GROUP-A")
}

// Test 8: File System Security And State Persistence
print("Test 8: File System Security And State Persistence")
do {
    let (tempDir, repoURL) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fs = FileSystemService.shared
    try! fs.writeFile(repoPath: repoURL.path, filePath: "hello.txt", content: "Hello miniOps")
    let readBack = try! fs.readFile(repoPath: repoURL.path, filePath: "hello.txt")
    assertEqual(readBack, "Hello miniOps", "Content read matches written")

    var readEscaped = false
    do {
        _ = try fs.readFile(repoPath: repoURL.path, filePath: "../secret.txt")
        readEscaped = true
    } catch {
        // Expected
    }
    assert(!readEscaped, "Reading outside repo must throw error")

    // State persistence
    let tempStateURL = tempDir.appendingPathComponent("custom-state.json")
    let stateStore = WorkspaceStateStore(customStorageURL: tempStateURL)
    var layout = RepoLayoutState()
    layout.selectedFilePath = "hello.txt"
    layout.terminalHeightRatio = 0.45
    layout.expandedFolderPaths = ["Sources", "Tests"]
    stateStore.saveRepoState(repoPath: repoURL.path, state: layout)

    let loaded = stateStore.getRepoState(repoPath: repoURL.path)
    assertEqual(loaded.selectedFilePath, "hello.txt", "Restored selected file path")
    assertEqual(loaded.terminalHeightRatio, 0.45, "Restored terminal height ratio")
    assertEqual(loaded.expandedFolderPaths, ["Sources", "Tests"], "Restored expanded folders")
}

print("==================================================")
print("Test Results: \(passedCount) passed, \(failedCount) failed")
print("==================================================")

if failedCount > 0 {
    exit(1)
}

// Test 9: End-to-End Workflow (Open -> Browse -> Edit -> Inspect Diff -> Commit Selected)
print("Test 9: End-to-End Workflow (Open -> Browse -> Edit -> Inspect Diff -> Commit Selected)")
do {
    let (tempDir, repoURL) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fs = FileSystemService.shared
    let gitService = GitService.shared

    // Create initial tree
    try! fs.writeFile(repoPath: repoURL.path, filePath: "src/main.swift", content: "print(\"hello world\")\n")
    try! fs.writeFile(repoPath: repoURL.path, filePath: "src/helper.swift", content: "func help() {}\n")
    try! fs.writeFile(repoPath: repoURL.path, filePath: "docs/readme.md", content: "# My Project\n")

    // Commit initial state
    _ = runGit(args: ["add", "-A"], in: repoURL.path)
    _ = runGit(args: ["commit", "-m", "Initial commit"], in: repoURL.path)

    // 1. Open / Scan repo
    let (branch, isDirty, _, _, initialChanges) = gitService.getRepoStatus(repoPath: repoURL.path)
    assertEqual(branch, "main", "Branch is main")
    assertEqual(isDirty, false, "Initial working tree is clean")
    assertEqual(initialChanges.count, 0, "No changes initially")

    // 2. Browse tree
    let tree = fs.buildFileTree(for: repoURL.path)
    assert(tree.children != nil && !tree.children!.isEmpty, "File tree has children")
    let srcDir = tree.children?.first(where: { $0.name == "src" })
    assert(srcDir != nil, "Found src directory")
    assert(srcDir?.isDirectory == true, "src is directory")

    // 3. Select and edit file
    var mainContent = try! fs.readFile(repoPath: repoURL.path, filePath: "src/main.swift")
    assertEqual(mainContent, "print(\"hello world\")\n")

    // Make an edit in src/main.swift and an unrelated change in docs/readme.md
    mainContent += "print(\"new line added\")\n"
    try! fs.writeFile(repoPath: repoURL.path, filePath: "src/main.swift", content: mainContent)
    try! fs.writeFile(repoPath: repoURL.path, filePath: "docs/readme.md", content: "# My Project\nUpdated docs\n")

    // 4. Inspect changes
    let (_, isDirtyAfterEdit, _, _, changesAfterEdit) = gitService.getRepoStatus(repoPath: repoURL.path)
    assert(isDirtyAfterEdit, "Repo is now dirty after edits")
    assertEqual(changesAfterEdit.count, 2, "Two files changed")

    // Inspect diff for src/main.swift
    let diffMain = gitService.getDiff(repoPath: repoURL.path, filePath: "src/main.swift")
    assert(diffMain.contains("+print(\"new line added\")"), "Diff contains added line")

    // 5. Commit ONLY src/main.swift (selective commit)
    let commitResult = gitService.selectiveCommit(
        repoPath: repoURL.path,
        message: "Update main.swift with new line",
        selectedPaths: ["src/main.swift"]
    )
    assert(commitResult.success, "Selective commit must succeed")

    // 6. Verify only src/main.swift was committed, while docs/readme.md remains modified
    let (_, isDirtyAfterCommit, _, _, changesAfterCommit) = gitService.getRepoStatus(repoPath: repoURL.path)
    assert(isDirtyAfterCommit, "Repo remains dirty because docs/readme.md was not committed")
    assertEqual(changesAfterCommit.count, 1, "Exactly one file remains changed")
    assertEqual(changesAfterCommit.first?.path, "docs/readme.md", "docs/readme.md remains uncommitted")

    let lastCommitFiles = runGit(args: ["show", "--pretty=", "--name-only", "HEAD"], in: repoURL.path)
    assertEqual(lastCommitFiles, "src/main.swift", "Last commit must ONLY contain src/main.swift")
}

// Test 10: Reconcile Partial Failure Handling
print("Test 10: Reconcile Partial Failure Handling")
do {
    let (tempDir, repoURL) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fs = FileSystemService.shared
    let gitService = GitService.shared

    try! fs.writeFile(repoPath: repoURL.path, filePath: "feature.txt", content: "feature code\n")

    // Set invalid remote to simulate push failure
    _ = runGit(args: ["remote", "add", "origin", "git@invalid.example.com:nonexistent.git"], in: repoURL.path)

    let reconcileResult = gitService.reconcile(repoPath: repoURL.path, message: "reconciling feature")
    assert(!reconcileResult.success, "Reconcile with broken remote should fail push")
    assert(reconcileResult.partialSuccess, "Must report partial success because commit was created locally")
    assert(reconcileResult.error?.contains("commit created, but push failed") == true, "Error message must state 'commit created, but push failed'")

    let lastCommitMsg = runGit(args: ["log", "-1", "--pretty=%s"], in: repoURL.path)
    assertEqual(lastCommitMsg, "reconciling feature", "Commit was created locally despite push failure")
}

print("==================================================")
print("All Extended Tests Completed: \(passedCount) passed, \(failedCount) failed")
print("==================================================")

if failedCount > 0 {
    exit(1)
}

// Test 11: Branch Creation and Checkout
print("Test 11: Branch Creation and Checkout")
do {
    let (tempDir, repoURL) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fs = FileSystemService.shared
    let gitService = GitService.shared

    try! fs.writeFile(repoPath: repoURL.path, filePath: "init.txt", content: "init\n")
    _ = runGit(args: ["add", "init.txt"], in: repoURL.path)
    _ = runGit(args: ["commit", "-m", "initial commit"], in: repoURL.path)

    let createRes = gitService.createBranch(repoPath: repoURL.path, branchName: "feature/login-ui")
    assert(createRes.success, "Branch creation should succeed")

    let currentBranch = runGit(args: ["branch", "--show-current"], in: repoURL.path)
    assertEqual(currentBranch, "feature/login-ui", "Switched to newly created branch")

    let branches = gitService.listBranches(repoPath: repoURL.path)
    assert(branches.contains("feature/login-ui"), "Branch list contains feature/login-ui")
    assert(branches.contains("main"), "Branch list contains main")

    let checkoutRes = gitService.checkout(repoPath: repoURL.path, branch: "main")
    assert(checkoutRes.success, "Checkout main should succeed")
    assertEqual(runGit(args: ["branch", "--show-current"], in: repoURL.path), "main", "Switched back to main")
}

// Test 12: Stash Creation, Listing, Inspection, and Safe Pop
print("Test 12: Stash Creation, Listing, Inspection, and Safe Pop")
do {
    let (tempDir, repoURL) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fs = FileSystemService.shared
    let gitService = GitService.shared

    try! fs.writeFile(repoPath: repoURL.path, filePath: "code.txt", content: "version 1\n")
    _ = runGit(args: ["add", "code.txt"], in: repoURL.path)
    _ = runGit(args: ["commit", "-m", "v1"], in: repoURL.path)

    // Make changes
    try! fs.writeFile(repoPath: repoURL.path, filePath: "code.txt", content: "version 2 (in progress)\n")
    try! fs.writeFile(repoPath: repoURL.path, filePath: "untracked.txt", content: "new notes\n")

    let initialStashes = gitService.listStashes(repoPath: repoURL.path)
    assertEqual(initialStashes.count, 0, "No stashes initially")

    let stashRes = gitService.stash(repoPath: repoURL.path, message: "WIP feature")
    assert(stashRes.success, "Stash should succeed")

    // Working tree is clean now
    let (_, isDirty, _, _, _) = gitService.getRepoStatus(repoPath: repoURL.path)
    assertEqual(isDirty, false, "Working tree is clean after stash")

    let stashes = gitService.listStashes(repoPath: repoURL.path)
    assertEqual(stashes.count, 1, "One stash item in list")
    assertEqual(stashes.first?.ref, "stash@{0}", "Stash ref matches stash@{0}")
    assert(stashes.first?.message.contains("WIP feature") == true, "Stash message preserved")

    // Inspect stash diff
    let stashDiff = gitService.showStash(repoPath: repoURL.path, stashRef: "stash@{0}")
    assert(stashDiff.contains("+version 2 (in progress)"), "Stash diff contains modified content")

    // Test safe pop: dirty tree blocks pop
    try! fs.writeFile(repoPath: repoURL.path, filePath: "blocker.txt", content: "dirty work\n")
    let dirtyPop = gitService.popStash(repoPath: repoURL.path, stashRef: "stash@{0}")
    assert(!dirtyPop.success, "Pop should fail when tree is dirty")
    assert(dirtyPop.error?.contains("clean working tree") == true, "Error message states clean tree required")

    // Clean blocker and pop
    _ = runGit(args: ["clean", "-fd"], in: repoURL.path)
    let cleanPop = gitService.popStash(repoPath: repoURL.path, stashRef: "stash@{0}")
    assert(cleanPop.success, "Pop succeeds when tree is clean")

    let readRestored = try! fs.readFile(repoPath: repoURL.path, filePath: "code.txt")
    assertEqual(readRestored, "version 2 (in progress)\n", "Stashed edits restored cleanly")
}

// Test 13: Worktree Listing and Management
print("Test 13: Worktree Listing and Management")
do {
    let (tempDir, repoURL) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fs = FileSystemService.shared
    let gitService = GitService.shared

    try! fs.writeFile(repoPath: repoURL.path, filePath: "README.md", content: "# Main\n")
    _ = runGit(args: ["add", "-A"], in: repoURL.path)
    _ = runGit(args: ["commit", "-m", "init"], in: repoURL.path)

    let worktrees = gitService.listWorktrees(repoPath: repoURL.path)
    assertEqual(worktrees.count, 1, "One main worktree initially")
    assert(worktrees.first?.isMain == true, "Is main worktree")

    let wtPath = tempDir.appendingPathComponent("wt-feature").path
    let addWtRes = gitService.addWorktree(repoPath: repoURL.path, worktreePath: wtPath, branch: nil, newBranch: "feat/worktree-test")
    assert(addWtRes.success, "Add worktree should succeed: \(addWtRes.error ?? "")")

    let updatedWts = gitService.listWorktrees(repoPath: repoURL.path)
    assertEqual(updatedWts.count, 2, "Two worktrees after addition")

    let rmRes = gitService.removeWorktree(repoPath: repoURL.path, worktreePath: wtPath, force: true)
    assert(rmRes.success, "Remove worktree should succeed")

    let finalWts = gitService.listWorktrees(repoPath: repoURL.path)
    assertEqual(finalWts.count, 1, "Back to one worktree after removal")
}

// Test 14: Batch Git Operations and Notes Service
print("Test 14: Batch Git Operations and Notes Service")
do {
    let (tempDir, repoURL) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let gitService = GitService.shared

    // Batch Git
    let batchRes = gitService.batchGit(action: "fetch", repoPaths: [repoURL.path])
    assertEqual(batchRes.totalCount, 1, "Total repos count is 1")
    assertEqual(batchRes.action, "fetch", "Batch action is fetch")

    // Notes Service
    let tempNotesURL = tempDir.appendingPathComponent("test-notes.json")
    let notesService = NotesService(customStorageURL: tempNotesURL)
    assertEqual(notesService.getNote(for: repoURL.path), "", "Initial note is empty")

    notesService.saveNote(for: repoURL.path, note: "Deployment checklist:\n1. run build\n2. check metrics")
    let retrieved = notesService.getNote(for: repoURL.path)
    assert(retrieved.contains("Deployment checklist"), "Retrieved saved note")

    // Verify persistence from disk
    let reloadedNotesService = NotesService(customStorageURL: tempNotesURL)
    assertEqual(reloadedNotesService.getNote(for: repoURL.path), retrieved, "Reloaded note matches from disk")
}

print("==================================================")
print("Complete Comprehensive Test Suite Finished: \(passedCount) passed, \(failedCount) failed")
print("==================================================")

if failedCount > 0 {
    exit(1)
}

// Test 15: Workspace Status Summary for Menu Bar Extra
print("Test 15: Workspace Status Summary for Menu Bar Extra")
do {
    let cleanSummary = WorkspaceStatusSummary(dirtyCount: 0, waitingAgentCount: 0)
    assertEqual(cleanSummary.type, .clean, "Clean summary when 0 dirty and 0 waiting")
    assertEqual(cleanSummary.title, "○", "Clean title is circle")

    let dirtySummary = WorkspaceStatusSummary(dirtyCount: 3, waitingAgentCount: 0)
    assertEqual(dirtySummary.type, .dirtyRepos(3), "Dirty repos status with count 3")
    assertEqual(dirtySummary.title, "● 3", "Dirty title shows count 3")
    assert(dirtySummary.tooltip.contains("3 repos with uncommitted changes"), "Tooltip mentions dirty count")

    let agentSummary = WorkspaceStatusSummary(dirtyCount: 2, waitingAgentCount: 1)
    assertEqual(agentSummary.type, .agentWaiting(1), "Agent waiting takes precedence over dirty repos")
    assertEqual(agentSummary.title, "● 1", "Agent waiting shows count 1")
    assert(agentSummary.tooltip.contains("1 agent waiting for input"), "Tooltip mentions agent waiting")
}

print("==================================================")
print("Complete Full Suite Finished: \(passedCount) passed, \(failedCount) failed")
print("==================================================")

if failedCount > 0 {
    exit(1)
}

// Test 16: Autonomous Agent Process Detection and Parsing
print("Test 16: Autonomous Agent Process Detection and Parsing")
do {
    let scanner = AgentScanner.shared
    let mockPsOutput = """
      PID     ELAPSED STAT TTY        %CPU COMMAND
    12345    00:15:30 S    ttys001     0.0 claude --model sonnet
    23456    01:00:00 R    ??         45.0 python3 train.py
    34567    00:05:22 S+   ttys002     0.0 /opt/homebrew/bin/aider --watch
    45678    00:02:10 R    ttys003    12.5 /Applications/ChatGPT.app/Contents/Resources/codex app-server
    56789    00:01:00 S    ??          0.0 grep claude
    """

    let agents = scanner.parsePsOutput(mockPsOutput, repositories: [])
    assertEqual(agents.count, 3, "Exactly 3 agents parsed (claude, aider, codex)")

    let claude = agents.first(where: { $0.tool == "Claude Code" })
    assert(claude != nil, "Claude Code agent found")
    assertEqual(claude?.pid, 12345, "Claude PID is 12345")
    assertEqual(claude?.isWaitingForInput, true, "Claude is waiting for input (TTY, S state, 0.0 CPU)")

    let aider = agents.first(where: { $0.tool == "Aider" })
    assert(aider != nil, "Aider agent found")
    assertEqual(aider?.isWaitingForInput, true, "Aider is waiting for input")

    let codex = agents.first(where: { $0.tool == "OpenAI Codex" })
    assert(codex != nil, "OpenAI Codex agent found")
    assertEqual(codex?.isWaitingForInput, false, "Codex is running (12.5 CPU)")

    // Verify ordering: waiting agents come first
    assertEqual(agents.first?.isWaitingForInput, true, "First agent in list is waiting for input")
}

print("==================================================")
print("All Milestone 4 Tests Completed: \(passedCount) passed, \(failedCount) failed")
print("==================================================")

if failedCount > 0 {
    exit(1)
}

// Test 17: Task / Ticket Scanning and Feature Branch Generation
print("Test 17: Task / Ticket Scanning and Feature Branch Generation")
do {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let ticketsDir = tempDir.appendingPathComponent("tickets")
    try! FileManager.default.createDirectory(at: ticketsDir, withIntermediateDirectories: true)

    let ticketFile = ticketsDir.appendingPathComponent("OPS-42-deploy.md")
    let ticketBody = """
    # Deploy to staging cluster
    Status: In Progress
    Priority: High

    Details about the deployment steps.
    """
    try! ticketBody.write(to: ticketFile, atomically: true, encoding: .utf8)

    let scanner = TicketScanner.shared
    let tickets = scanner.scanTickets(workspacePath: tempDir.path)

    assertEqual(tickets.count, 1, "One ticket scanned")
    let ticket = tickets.first
    assertEqual(ticket?.key, "OPS-42", "Key is OPS-42")
    assertEqual(ticket?.summary, "Deploy to staging cluster", "Summary parsed from H1")
    assertEqual(ticket?.status, "In Progress", "Status is In Progress")
    assertEqual(ticket?.priority, "High", "Priority is High")
    assertEqual(ticket?.isOpen, true, "Ticket is open")

    let branchName = scanner.makeFeatureBranchName(ticket: ticket!)
    assertEqual(branchName, "feat/OPS-42-deploy-to-staging-cluster", "Feature branch generated with slug")
}

print("==================================================")
print("All Milestone 5 Tests Completed: \(passedCount) passed, \(failedCount) failed")
print("==================================================")

if failedCount > 0 {
    exit(1)
}

// Test 18: Knowledge Graph and Graphify Scanner
print("Test 18: Knowledge Graph and Graphify Scanner")
do {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let graphDir = tempDir.appendingPathComponent("graphify-out")
    try! FileManager.default.createDirectory(at: graphDir, withIntermediateDirectories: true)

    let graphJSON = """
    {
        "nodes": [
            { "id": "A", "label": "GodService", "community": 1, "community_name": "Core", "file_type": "swift", "source_file": "Sources/Core.swift" },
            { "id": "B", "label": "HelperOne", "community": 1, "community_name": "Core", "file_type": "swift" },
            { "id": "C", "label": "HelperTwo", "community": 2, "community_name": "Utils", "file_type": "swift" },
            { "id": "D", "label": "HelperThree", "community": 2, "community_name": "Utils", "file_type": "swift" }
        ],
        "links": [
            { "source": "A", "target": "B", "relation": "calls" },
            { "source": "A", "target": "C", "relation": "uses" },
            { "source": "A", "target": "D", "relation": "owns" }
        ]
    }
    """
    try! graphJSON.write(to: graphDir.appendingPathComponent("graph.json"), atomically: true, encoding: .utf8)
    try! "# Architecture Report\n".write(to: graphDir.appendingPathComponent("GRAPH_REPORT.md"), atomically: true, encoding: .utf8)

    let scanner = GraphifyScanner.shared
    let graphData = scanner.loadGraph(for: tempDir.path, workspacePath: tempDir.path)

    assert(graphData != nil, "Graph data loaded successfully")
    assertEqual(graphData?.nodes.count, 4, "Loaded 4 nodes")
    assertEqual(graphData?.links.count, 3, "Loaded 3 links")
    assertEqual(graphData?.communities.count, 2, "2 communities detected")
    assert(graphData?.reportPath != nil, "GRAPH_REPORT.md detected")

    let godNodes = scanner.computeGodNodes(data: graphData!, limit: 5)
    assertEqual(godNodes.first?.node.id, "A", "Node A is ranked top god node")
    assertEqual(godNodes.first?.degree, 3, "Node A has degree 3")
}

print("==================================================")
print("Complete 100% Full Feature Test Suite: \(passedCount) passed, \(failedCount) failed")
print("==================================================")

if failedCount > 0 {
    exit(1)
}

// Regression coverage for empty selections, literal status names, and file boundaries.
do {
    let (tempDir, repoURL) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let names = ["café.txt", " leading.txt", "arrow -> name.txt", "line\nbreak.txt"]
    for name in names {
        try! "content".write(to: repoURL.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    let service = GitService()
    assertEqual(Set(service.getRepoStatus(repoPath: repoURL.path).changes.map { $0.path }), Set(names), "Status preserves literal filenames")
    let result = service.reconcile(repoPath: repoURL.path, selectedPaths: [])
    assert(!result.success && !result.partialSuccess, "Empty selection must not create a commit")
    assert(runGit(args: ["log", "--oneline"], in: repoURL.path).contains("does not have any commits"), "No commit was created")
    let fs = FileSystemService()
    let sibling = repoURL.path + "-other/file.txt"
    assert(fs.validatePathWithin(repoPath: repoURL.path, filePath: sibling) == nil, "Reject sibling prefix")
    let outside = tempDir.appendingPathComponent("outside")
    try! FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try! FileManager.default.createSymbolicLink(at: repoURL.appendingPathComponent("escape"), withDestinationURL: outside)
    assert(fs.validatePathWithin(repoPath: repoURL.path, filePath: "escape/file.txt") == nil, "Reject symlink escape")
    assert(fs.validatePathWithin(repoPath: repoURL.path, filePath: names[0]) != nil, "Allow repository file")
}
print("Safety regression total: \(passedCount) passed, \(failedCount) failed")
if failedCount > 0 { exit(1) }

// Test 19: GitHub Repository Cloning and Remote Creation Validation
print("Test 19: GitHub Repository Cloning and Remote Creation Validation")
do {
    let ghService = GitHubService.shared

    // Name validation
    assertEqual(ghService.validateRepoName("my-app").valid, true, "Valid repo name 'my-app'")
    assertEqual(ghService.validateRepoName("Project_123.swift").valid, true, "Valid repo name with underscores and dots")
    assertEqual(ghService.validateRepoName("").valid, false, "Empty repo name is invalid")
    assertEqual(ghService.validateRepoName(".").valid, false, "Single dot repo name is invalid")
    assertEqual(ghService.validateRepoName("..").valid, false, "Double dot repo name is invalid")
    assertEqual(ghService.validateRepoName("invalid/repo").valid, false, "Slash in repo name is invalid")
    assertEqual(ghService.validateRepoName("repo with spaces").valid, false, "Spaces in repo name are invalid")

    // Folder name derivation
    assertEqual(ghService.deriveFolderName(from: "https://github.com/marcelodevops/miniOps.git"), "miniOps", "Derive folder from https git url")
    assertEqual(ghService.deriveFolderName(from: "git@github.com:owner/custom-project.git"), "custom-project", "Derive folder from ssh git url")
    assertEqual(ghService.deriveFolderName(from: "marcelodevops/openclaw"), "openclaw", "Derive folder from owner/name shorthand")
    assertEqual(ghService.deriveFolderName(from: "my-standalone-repo"), "my-standalone-repo", "Derive folder from simple name")

    // Destination checks
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("miniOps-clone-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Pre-create an existing folder
    let existingDir = tempDir.appendingPathComponent("existing-repo")
    try! FileManager.default.createDirectory(at: existingDir, withIntermediateDirectories: true)

    // Clone rejects empty URL
    let emptyClone = ghService.cloneRepository(urlOrName: "", destinationDirectory: tempDir.path)
    assertEqual(emptyClone.success, false, "Clone rejects empty URL")

    // Clone rejects existing destination
    let existingClone = ghService.cloneRepository(urlOrName: "https://github.com/foo/existing-repo.git", destinationDirectory: tempDir.path)
    assertEqual(existingClone.success, false, "Clone rejects existing target directory")

    // Clone rejects non-existent destination directory
    let badDestClone = ghService.cloneRepository(urlOrName: "https://github.com/foo/bar.git", destinationDirectory: "/nonexistent/path/\(UUID().uuidString)")
    assertEqual(badDestClone.success, false, "Clone rejects non-existent destination directory")

    // Create remote rejects invalid repo name
    let badNameCreate = ghService.createAndCloneRemoteRepository(name: "../bad..name", isPrivate: true, destinationDirectory: tempDir.path)
    assertEqual(badNameCreate.success, false, "Create remote rejects invalid repo name")

    // Create remote rejects existing destination
    let existingCreate = ghService.createAndCloneRemoteRepository(name: "existing-repo", isPrivate: true, destinationDirectory: tempDir.path)
    assertEqual(existingCreate.success, false, "Create remote rejects existing target directory")

    // Create remote rejects non-existent destination
    let badDestCreate = ghService.createAndCloneRemoteRepository(name: "new-repo", isPrivate: true, destinationDirectory: "/nonexistent/path/\(UUID().uuidString)")
    assertEqual(badDestCreate.success, false, "Create remote rejects non-existent destination directory")
}

// Test 20: Repository Hiding, Persistence, and Settings Re-import
print("Test 20: Repository Hiding, Persistence, and Settings Re-import")
do {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().appendingPathComponent("miniOps-hidden-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let stateFile = tempDir.appendingPathComponent("state.json")
    let stateStore = WorkspaceStateStore(customStorageURL: stateFile)

    // Initially empty
    assertEqual(stateStore.getHiddenRepoPaths().count, 0, "Initially no hidden repos")
    assertEqual(stateStore.getCustomRepoPaths().count, 0, "Initially no custom repos")

    // Hide repos
    let repoPathA = tempDir.appendingPathComponent("repoA").resolvingSymlinksInPath().path
    let repoPathB = tempDir.appendingPathComponent("repoB").resolvingSymlinksInPath().path
    stateStore.hideRepo(path: repoPathA)
    stateStore.hideRepo(path: repoPathB)

    assertEqual(stateStore.getHiddenRepoPaths().count, 2, "Two repos hidden")
    assert(stateStore.getHiddenRepoPaths().contains(repoPathA), "Hidden repos contains repoA")
    assert(stateStore.getHiddenRepoPaths().contains(repoPathB), "Hidden repos contains repoB")

    // Verify persistence across store reloads
    let reloadedStore = WorkspaceStateStore(customStorageURL: stateFile)
    assertEqual(reloadedStore.getHiddenRepoPaths().count, 2, "Reloaded store persists hidden repos")
    assert(reloadedStore.getHiddenRepoPaths().contains(repoPathA), "Reloaded store contains repoA")

    // Unhide one repo
    stateStore.unhideRepo(path: repoPathA)
    assertEqual(stateStore.getHiddenRepoPaths().count, 1, "Unhide leaves one repo")
    assertEqual(stateStore.getHiddenRepoPaths().contains(repoPathA), false, "repoA is no longer hidden")
    assertEqual(stateStore.getHiddenRepoPaths().contains(repoPathB), true, "repoB is still hidden")

    // Unhide all
    stateStore.unhideAllRepos()
    assertEqual(stateStore.getHiddenRepoPaths().count, 0, "Unhide all clears all hidden repos")

    // Custom repo paths
    let customPath = tempDir.appendingPathComponent("external-repo").resolvingSymlinksInPath().path
    stateStore.addCustomRepo(path: customPath)
    assertEqual(stateStore.getCustomRepoPaths().contains(customPath), true, "Custom repo added")

    let reloadedCustomStore = WorkspaceStateStore(customStorageURL: stateFile)
    assertEqual(reloadedCustomStore.getCustomRepoPaths().contains(customPath), true, "Custom repo persisted across reloads")

    stateStore.removeCustomRepo(path: customPath)
    assertEqual(stateStore.getCustomRepoPaths().contains(customPath), false, "Custom repo removed")

    // WorkspaceScanner integration
    let wsDir = tempDir.appendingPathComponent("workspace").resolvingSymlinksInPath()
    let repo1Dir = wsDir.appendingPathComponent("project1").resolvingSymlinksInPath()
    let repo2Dir = wsDir.appendingPathComponent("project2").resolvingSymlinksInPath()
    let extRepoDir = tempDir.appendingPathComponent("external-project").resolvingSymlinksInPath()

    try! FileManager.default.createDirectory(at: repo1Dir, withIntermediateDirectories: true)
    try! FileManager.default.createDirectory(at: repo2Dir, withIntermediateDirectories: true)
    try! FileManager.default.createDirectory(at: extRepoDir, withIntermediateDirectories: true)

    _ = runGit(args: ["init", "-b", "main"], in: repo1Dir.path)
    _ = runGit(args: ["init", "-b", "main"], in: repo2Dir.path)
    _ = runGit(args: ["init", "-b", "main"], in: extRepoDir.path)

    let scanner = WorkspaceScanner.shared

    // Direct inspection
    let inspected = scanner.inspectRepo(path: repo1Dir.path)
    assert(inspected != nil, "inspectRepo finds valid git repo")
    assertEqual(inspected?.name, "project1", "inspected repo has correct name")

    let nonGit = scanner.inspectRepo(path: tempDir.path)
    assert(nonGit == nil, "inspectRepo returns nil for non-git directory")

    // Scan workspace
    let wsRepos = scanner.scan(rootPath: wsDir.path)
    assertEqual(wsRepos.count, 2, "Workspace scan finds 2 repos")

    // Scan with custom external repo
    let wsReposWithCustom = scanner.scan(rootPath: wsDir.path, customPaths: [extRepoDir.path])
    assertEqual(wsReposWithCustom.count, 3, "Scan includes custom external repo")
    assert(wsReposWithCustom.contains(where: { $0.path == extRepoDir.path }), "Contains external repo")

    // Filter hidden repos
    let hiddenSet: Set<String> = [repo1Dir.path]
    let visibleRepos = wsReposWithCustom.filter { !hiddenSet.contains($0.path) }
    assertEqual(visibleRepos.count, 2, "Hidden repo is filtered out from visible list")
    assertEqual(visibleRepos.contains(where: { $0.path == repo1Dir.path }), false, "Hidden repo is excluded")
    assertEqual(visibleRepos.contains(where: { $0.path == repo2Dir.path }), true, "Non-hidden repo remains")
    assertEqual(visibleRepos.contains(where: { $0.path == extRepoDir.path }), true, "External repo remains")
}

// Test 21: Herdr Service, Socket API, and Agent Lifecycle Parsing
print("Test 21: Herdr Service, Socket API, and Agent Lifecycle Parsing")
do {
    let herdr = HerdrService.shared

    // Status parsing
    let sampleStatus = """
    client:
      version: 0.8.2
      channel: stable
      protocol: 20

    server:
      status: running
      version: 0.8.2
      protocol: 20
      socket: /Users/mac/.config/herdr/herdr.sock
    """
    let statusInfo = herdr.parseStatusOutput(sampleStatus)
    assertEqual(statusInfo.isRunning, true, "Status reports server running")
    assertEqual(statusInfo.version, "0.8.2", "Parsed server version")
    assertEqual(statusInfo.socketPath, "/Users/mac/.config/herdr/herdr.sock", "Parsed socket path")

    // Agent list JSON parsing
    let sampleAgentJSON = """
    {
      "id": "cli:agent:list",
      "result": {
        "agents": [
          {
            "agent": "copilot",
            "agent_status": "idle",
            "cwd": "/Users/mac/repos/myops-os",
            "pane_id": "w1:p2",
            "workspace_id": "w1",
            "tab_id": "w1:t2",
            "terminal_title": "Review Work In Progress",
            "focused": false
          },
          {
            "agent": "agy",
            "agent_status": "working",
            "cwd": "/Users/mac/repos/miniOps",
            "pane_id": "w3:p2",
            "workspace_id": "w3",
            "tab_id": "w3:t1",
            "terminal_title": "Build MiniOps",
            "focused": true
          },
          {
            "agent": "claude",
            "agent_status": "blocked",
            "cwd": "/Users/mac/repos/myops-os",
            "pane_id": "w2:p1",
            "workspace_id": "w2",
            "tab_id": "w2:t1",
            "terminal_title": "Claude Prompt Confirmation",
            "focused": false
          }
        ],
        "type": "agent_list"
      }
    }
    """.data(using: .utf8)!

    let parsedAgents = herdr.parseAgentListJSON(sampleAgentJSON)
    assertEqual(parsedAgents.count, 3, "Parsed 3 Herdr agents from JSON")
    assertEqual(parsedAgents[0].agent, "copilot", "Agent 1 is copilot")
    assertEqual(parsedAgents[1].agentStatus, "working", "Agent 2 is working")
    assertEqual(parsedAgents[2].agentStatus, "blocked", "Agent 3 is blocked")
    assertEqual(parsedAgents[2].paneId, "w2:p1", "Agent 3 paneId is w2:p1")

    // Integration status output parsing
    let sampleIntegrations = """
    claude: current (v8) (/Users/mac/.claude/hooks/herdr-agent-state.sh)
    codex: current (v8) (/Users/mac/.codex/herdr-agent-state.sh)
    antigravity-cli: current (v2) (/Users/mac/.gemini/config/hooks/herdr-agent-state.sh)
    cursor: not installed (/Users/mac/.cursor/herdr-agent-state.sh)
    """
    let integrations = herdr.parseIntegrationStatusOutput(sampleIntegrations)
    assertEqual(integrations.count, 4, "Parsed 4 integrations")
    assertEqual(integrations[0].target, "claude", "First integration is claude")
    assertEqual(integrations[0].isInstalled, true, "claude is installed")
    assertEqual(integrations[2].target, "antigravity-cli", "Third integration is antigravity-cli")
    assertEqual(integrations[2].isInstalled, true, "antigravity-cli is installed")
    assertEqual(integrations[3].target, "cursor", "Fourth integration is cursor")
    assertEqual(integrations[3].isInstalled, false, "cursor is not installed")

    // AgentScanner merging with Herdr
    let scanner = AgentScanner.shared
    let dummyRepo = RepoInfo(name: "miniOps", path: "/Users/mac/repos/miniOps", branch: "main", isDirty: false, ahead: 0, behind: 0)
    let standalonePsAgent = AgentInfo(pid: 9999, tool: "Aider", status: "running", isWaitingForInput: false, elapsed: "01:00", cpu: 1.2, tty: "ttys004", repoName: "other", repoPath: "/other", command: "aider")

    let merged = scanner.mergeHerdrAgents(parsedAgents, psAgents: [standalonePsAgent], repositories: [dummyRepo])
    assertEqual(merged.count, 4, "Merged 3 Herdr agents + 1 standalone ps agent = 4 agents")

    // Blocked Herdr agent (Claude) should be first because it is waiting for input
    assertEqual(merged[0].tool, "Claude Code", "Waiting/blocked agent is sorted first")
    assertEqual(merged[0].isWaitingForInput, true, "Blocked agent has isWaitingForInput = true")
    assertEqual(merged[0].herdrStatus, "blocked", "Herdr status preserved")
    assertEqual(merged[0].isHerdrManaged, true, "Marked as Herdr managed")

    // Antigravity agent mapped correctly
    let agyAgent = merged.first(where: { $0.tool == "Google Antigravity" })
    assert(agyAgent != nil, "Google Antigravity agent present in merged list")
    assertEqual(agyAgent?.herdrPaneId, "w3:p2", "Antigravity pane ID matched")
    assertEqual(agyAgent?.repoName, "miniOps", "Antigravity matched repo miniOps")
    assertEqual(agyAgent?.isHerdrManaged, true, "Antigravity is Herdr managed")

    // Standalone agent preserved
    let aiderAgent = merged.first(where: { $0.tool == "Aider" })
    assert(aiderAgent != nil, "Standalone Aider agent preserved")
    assertEqual(aiderAgent?.isHerdrManaged, false, "Standalone agent is not Herdr managed")

    // Live executable test
    if let exe = herdr.findExecutable() {
        assert(FileManager.default.isExecutableFile(atPath: exe), "Found valid executable herdr")
    }

    let workspaceResult = HerdrWorkspaceResult(success: true, workspaceID: "w-test", message: "created")
    assertEqual(workspaceResult.workspaceID, "w-test", "Workspace result preserves created workspace ID")
}

// Test 22: Add, Commit and Push in a Single Step (xgit)
print("Test 22: Add, Commit and Push in a Single Step (xgit)")
do {
    let (tempDir, repoURL) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let gitService = GitService.shared

    // Local bare repository acting as "origin" so the push really happens.
    let remoteURL = tempDir.appendingPathComponent("origin.git")
    _ = runGit(args: ["init", "--bare", "-b", "main", remoteURL.path], in: tempDir.path)
    _ = runGit(args: ["remote", "add", "origin", remoteURL.path], in: repoURL.path)

    // Empty message is rejected before touching the repository.
    let emptyMsg = gitService.addCommitPush(repoPath: repoURL.path, message: "   ")
    assert(!emptyMsg.success, "addCommitPush must reject an empty commit message")

    // Clean repository has nothing to stage, exactly like xgit's --cached guard.
    let cleanResult = gitService.addCommitPush(repoPath: repoURL.path, message: "no changes")
    assert(!cleanResult.success, "addCommitPush must fail on a clean repository")
    assert(cleanResult.error?.contains("Nothing to commit") == true, "Clean repository reports 'Nothing to commit'")

    try! FileSystemService.shared.writeFile(repoPath: repoURL.path, filePath: "src/app.swift", content: "print(\"xgit\")\n")

    // First push has no upstream yet, so it must set one automatically.
    let result = gitService.addCommitPush(repoPath: repoURL.path, message: "feat: add app entry point")
    assert(result.success, "addCommitPush must stage, commit and push in one step")

    assertEqual(runGit(args: ["log", "-1", "--pretty=%s"], in: repoURL.path), "feat: add app entry point", "Custom commit message was used")
    assertEqual(runGit(args: ["show", "--pretty=", "--name-only", "HEAD"], in: repoURL.path), "src/app.swift", "All changes were staged and committed")
    assertEqual(runGit(args: ["rev-parse", "--abbrev-ref", "@{upstream}"], in: repoURL.path), "origin/main", "Upstream was set on first push")
    assertEqual(
        runGit(args: ["rev-parse", "HEAD"], in: repoURL.path),
        runGit(args: ["--git-dir", remoteURL.path, "rev-parse", "main"], in: tempDir.path),
        "Remote received the new commit"
    )

    let (_, isDirtyAfter, ahead, _, _) = gitService.getRepoStatus(repoPath: repoURL.path)
    assert(!isDirtyAfter, "Working tree is clean after add/commit/push")
    assertEqual(ahead, 0, "Nothing left to push after addCommitPush")
}

print("==================================================")
print("Complete Full miniOps Test Suite: \(passedCount) passed, \(failedCount) failed")
print("==================================================")
if failedCount > 0 { exit(1) }
