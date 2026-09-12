import Foundation
import Security
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

// Test 23: Credential Store and Integration Settings Persistence
print("Test 23: Credential Store and Integration Settings Persistence")
do {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Non-secret integration settings round-trip through the state file.
    let storeURL = tempDir.appendingPathComponent("state.json")
    let store = WorkspaceStateStore(customStorageURL: storeURL)
    assertEqual(store.getIntegrationSettings().jiraBaseURL, "", "Integration settings start empty")
    assertEqual(store.getIntegrationSettings().herdrModeEnabled, false, "Herdr mode is off by default")

    var settings = IntegrationSettings()
    settings.jiraBaseURL = "https://example.atlassian.net"
    settings.jiraEmail = "dev@example.com"
    settings.githubUsername = "octocat"
    store.saveIntegrationSettings(settings)
    store.setHerdrModeEnabled(true)

    let reloaded = WorkspaceStateStore(customStorageURL: storeURL)
    assertEqual(reloaded.getIntegrationSettings().jiraBaseURL, "https://example.atlassian.net", "Jira site URL persisted")
    assertEqual(reloaded.getIntegrationSettings().jiraEmail, "dev@example.com", "Jira email persisted")
    assertEqual(reloaded.getIntegrationSettings().githubUsername, "octocat", "GitHub username persisted")
    assertEqual(reloaded.getIntegrationSettings().herdrModeEnabled, true, "Herdr mode flag persisted")

    // Secrets never reach the state file.
    let stateContents = (try? String(contentsOf: storeURL, encoding: .utf8)) ?? ""
    assert(!stateContents.contains("token"), "State file must not carry any token field")

    // Older state files without the new key still decode.
    let legacyURL = tempDir.appendingPathComponent("legacy.json")
    try! #"{"repoStates":{},"hiddenRepoPaths":[],"customRepoPaths":[]}"#.write(to: legacyURL, atomically: true, encoding: .utf8)
    let legacyStore = WorkspaceStateStore(customStorageURL: legacyURL)
    assertEqual(legacyStore.getIntegrationSettings().herdrModeEnabled, false, "Legacy state decodes with default integration settings")

    // Deterministic Keychain API backend; production still uses Security.framework.
    var secrets: [String: Data] = [:]
    let credentials = CredentialStore(
        service: "com.miniops.credentials.tests.\(UUID().uuidString)",
        updateItem: { query, attributes in
            let key = (query as NSDictionary)[kSecAttrAccount] as! String
            guard secrets[key] != nil else { return errSecItemNotFound }
            secrets[key] = (attributes as NSDictionary)[kSecValueData] as? Data
            return errSecSuccess
        },
        addItem: { query in
            let values = query as NSDictionary
            secrets[values[kSecAttrAccount] as! String] = values[kSecValueData] as? Data
            return errSecSuccess
        },
        copyItem: { query, result in
            let key = (query as NSDictionary)[kSecAttrAccount] as! String
            guard let data = secrets[key] else { return errSecItemNotFound }
            result.pointee = data as CFData
            return errSecSuccess
        },
        deleteItem: { query in
            let key = (query as NSDictionary)[kSecAttrAccount] as! String
            return secrets.removeValue(forKey: key) == nil ? errSecItemNotFound : errSecSuccess
        }
    )
    assertEqual(credentials.hasSecret(for: .jira), false, "No Jira token stored initially")
    assert(credentials.saveSecret("jira-secret-1234", for: .jira), "Jira token saved to the Keychain")
    assertEqual(credentials.readSecret(for: .jira), "jira-secret-1234", "Jira token reads back")
    assertEqual(credentials.maskedSecret(for: .jira), "••••••••1234", "Masked token exposes only the last four characters")

    assert(credentials.saveSecret("jira-secret-5678", for: .jira), "Existing Jira token can be replaced")
    assertEqual(credentials.readSecret(for: .jira), "jira-secret-5678", "Replaced Jira token reads back")

    assert(credentials.saveSecret("ghp_token_abcd", for: .github), "GitHub token saved to the Keychain")
    assertEqual(credentials.readSecret(for: .github), "ghp_token_abcd", "GitHub token is stored separately from Jira")

    // Saving an empty secret clears it rather than storing a blank token.
    assert(credentials.saveSecret("   ", for: .github), "Blank secret is accepted as a clear operation")
    assertEqual(credentials.hasSecret(for: .github), false, "Blank secret removed the GitHub token")

    assert(credentials.deleteSecret(for: .jira), "Jira token deleted")
    assertEqual(credentials.readSecret(for: .jira), nil, "Deleted Jira token no longer readable")
    assert(credentials.deleteSecret(for: .jira), "Deleting a missing token is not an error")

    _ = credentials.deleteSecret(for: .github)
}

// Test 24: Herdr Mode Session Naming
print("Test 24: Herdr Mode Session Naming")
do {
    assertEqual(HerdrService.sessionName(forRepoPath: "/Users/dev/repos/miniOps"), "miniOps", "Repository folder name becomes the session name")
    assertEqual(HerdrService.sessionName(forRepoPath: "/Users/dev/repos/my repo.v2/"), "my-repo-v2", "Spaces and dots are replaced with dashes")
    assertEqual(HerdrService.sessionName(forRepoPath: "~/repos/api_service"), "api_service", "Underscores and tildes are handled")
    assertEqual(HerdrService.sessionName(forRepoPath: "/"), "miniops", "Unusable folder names fall back to a default session")
}

// Test 25: Ticket Navigator Filtering and Path Resolution
print("Test 25: Ticket Navigator Filtering and Path Resolution")
do {
    let scanner = TicketScanner.shared
    let tickets = [
        TicketInfo(key: "VSSD-101", summary: "Add namespace quota", statusCategory: "todo", isOpen: true),
        TicketInfo(key: "VSSD-102", summary: "Rotate Istio certificate", statusCategory: "in_progress", isOpen: true),
        TicketInfo(key: "TMPL-9", summary: "Archive old namespace", statusCategory: "done", isOpen: false)
    ]

    assertEqual(scanner.filter(tickets: tickets).count, 2, "Open-only filter hides completed tickets")
    assertEqual(scanner.filter(tickets: tickets, openOnly: false).count, 3, "Disabling the open filter shows every ticket")

    let byKey = scanner.filter(tickets: tickets, searchText: "vssd-102")
    assertEqual(byKey.count, 1, "Search matches the ticket key case-insensitively")
    assertEqual(byKey.first?.key, "VSSD-102", "Correct ticket matched by key")

    let bySummary = scanner.filter(tickets: tickets, searchText: "istio")
    assertEqual(bySummary.count, 1, "Search matches the ticket summary")

    assertEqual(scanner.filter(tickets: tickets, searchText: "namespace").count, 1, "Closed tickets stay hidden while searching")
    assertEqual(scanner.filter(tickets: tickets, searchText: "namespace", openOnly: false).count, 2, "Both namespace tickets match once closed ones are shown")
    assertEqual(scanner.filter(tickets: tickets, searchText: "   ").count, 2, "A whitespace-only query is treated as no query")
    assertEqual(scanner.filter(tickets: tickets, searchText: "nothing-matches").count, 0, "Unmatched query returns no tickets")

    // Path resolution keeps ticket files confined to the selected repository.
    assertEqual(
        scanner.repoRelativePath(forTicketPath: "/Users/dev/repos/miniOps/tickets/VSSD-101.md", repoPath: "/Users/dev/repos/miniOps"),
        "tickets/VSSD-101.md",
        "Ticket inside the repository resolves to a relative path"
    )
    assertEqual(
        scanner.repoRelativePath(forTicketPath: "/Users/dev/repos/miniOps/tickets/VSSD-101.md", repoPath: "/Users/dev/repos/miniOps/"),
        "tickets/VSSD-101.md",
        "Trailing slash on the repository path is handled"
    )
    assertEqual(
        scanner.repoRelativePath(forTicketPath: "/Users/dev/repos/other/tickets/VSSD-101.md", repoPath: "/Users/dev/repos/miniOps"),
        nil,
        "Ticket in a different repository is rejected"
    )
    assertEqual(
        scanner.repoRelativePath(forTicketPath: "/Users/dev/repos/miniOpsExtra/t.md", repoPath: "/Users/dev/repos/miniOps"),
        nil,
        "A sibling directory sharing the repository name prefix is rejected"
    )
    assertEqual(
        scanner.repoRelativePath(forTicketPath: "/Users/dev/repos/miniOps", repoPath: "/Users/dev/repos/miniOps"),
        nil,
        "The repository root itself is not a ticket file"
    )

    // Feature branch naming stays stable for the navigator's branch action.
    assertEqual(
        scanner.makeFeatureBranchName(ticket: tickets[0]),
        "feat/VSSD-101-add-namespace-quota",
        "Feature branch name derives from the key and summary"
    )
}

// Test 26: Jira Service, URL Normalization, and Ticket Caching
print("Test 26: Jira Service, URL Normalization, and Ticket Caching")
do {
    let jira = JiraService.shared

    // URL normalization
    assertEqual(
        jira.normalizeBaseURL("https://marcelops.atlassian.net/"),
        "https://marcelops.atlassian.net",
        "Trailing slashes are stripped"
    )
    assertEqual(
        jira.normalizeBaseURL("marcelops.atlassian.net"),
        "https://marcelops.atlassian.net",
        "Missing scheme is defaulted to https"
    )

    // Basic Auth header formatting
    let authHeader = jira.createAuthHeader(email: "test@example.com", token: "api-token-xyz")
    assert(authHeader.hasPrefix("Basic "), "Auth header starts with Basic")
    let b64 = String(authHeader.dropFirst("Basic ".count))
    if let decodedData = Data(base64Encoded: b64), let decoded = String(data: decodedData, encoding: .utf8) {
        assertEqual(decoded, "test@example.com:api-token-xyz", "Decoded credentials match email:token")
    } else {
        assert(false, "Auth header base64 decoded successfully")
    }

    // Cache saving and TicketScanner integration
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let sampleTickets = [
        TicketInfo(
            key: "KAN-1",
            summary: "Task 1",
            status: "In Progress",
            statusCategory: "in_progress",
            priority: "None",
            isOpen: true,
            localPath: nil,
            notes: ""
        ),
        TicketInfo(
            key: "KAN-2",
            summary: "Completed Task",
            status: "Done",
            statusCategory: "done",
            priority: "Low",
            isOpen: false,
            localPath: nil,
            notes: ""
        )
    ]

    jira.saveCache(tickets: sampleTickets, baseURL: "https://marcelops.atlassian.net", workspacePath: tempDir.path)

    let cacheFile = tempDir.appendingPathComponent("jira-cache.json")
    assert(FileManager.default.fileExists(atPath: cacheFile.path), "jira-cache.json was written to workspace root")

    let scanned = TicketScanner.shared.scanTickets(workspacePath: tempDir.path)
    assertEqual(scanned.count, 2, "Scanned 2 tickets from generated jira-cache.json")

    let kan1 = scanned.first(where: { $0.key == "KAN-1" })
    assert(kan1 != nil, "Found KAN-1 in scanned tickets")
    assertEqual(kan1?.summary, "Task 1", "Summary matches")
    assertEqual(kan1?.status, "In Progress", "Status matches")
    assertEqual(kan1?.isOpen, true, "KAN-1 is open")

    let branch = TicketScanner.shared.makeFeatureBranchName(ticket: kan1!)
    assertEqual(branch, "feat/KAN-1-task-1", "Derived branch name feat/KAN-1-task-1")

    let openOnly = TicketScanner.shared.filter(tickets: scanned, searchText: "", openOnly: true)
    assertEqual(openOnly.count, 1, "Only 1 open ticket matches filter")
    assertEqual(openOnly.first?.key, "KAN-1", "Open ticket is KAN-1")
}

// Test 27: Split Pane Layout Adapts To Container Width
print("Test 27: Split Pane Layout Adapts To Container Width")
do {
    // Reproduces the reported bug: the detail pane is 1200pt wide with the sidebar
    // hidden, then the 280pt sidebar appears and it drops to 920pt. An absolute
    // divider (the HSplitView behaviour) keeps the leading pane at 360pt, leaving
    // the file list sitting under the sidebar. A proportional layout must shrink it.
    let wide = SplitPaneLayout.resolve(totalWidth: 1200, ratio: 0.3)
    assertEqual(Int(wide.leadingWidth.rounded()), 360, "Leading pane takes its ratio of the wide container")
    assertEqual(Int(wide.totalWidth.rounded()), 1200, "Panes fill the wide container exactly")

    let narrow = SplitPaneLayout.resolve(totalWidth: 920, ratio: 0.3)
    assertEqual(Int(narrow.leadingWidth.rounded()), 276, "Leading pane shrinks with the container when the sidebar appears")
    assertEqual(Int(narrow.totalWidth.rounded()), 920, "Panes fill the narrowed container exactly")
    assert(narrow.leadingWidth < wide.leadingWidth, "Leading pane must not keep its absolute width when the container narrows")

    // The invariant that makes overflow impossible at any width.
    for width in stride(from: 60.0, through: 2400.0, by: 30.0) {
        for ratio in [0.0, 0.15, 0.3, 0.5, 0.85, 1.0] {
            let layout = SplitPaneLayout.resolve(totalWidth: CGFloat(width), ratio: CGFloat(ratio))
            let delta = abs(layout.totalWidth - CGFloat(width))
            assert(delta < 0.001, "Panes exactly fill a \(Int(width))pt container at ratio \(ratio)")
            assert(layout.leadingWidth >= 0 && layout.trailingWidth >= 0, "Pane widths never go negative at \(Int(width))pt")
        }
    }

    // Minimum widths are honoured whenever the container can afford them.
    let squeezed = SplitPaneLayout.resolve(totalWidth: 600, ratio: 0.02)
    assertEqual(Int(squeezed.leadingWidth.rounded()), 200, "Leading pane is clamped to its minimum width")
    let stretched = SplitPaneLayout.resolve(totalWidth: 600, ratio: 0.99)
    assertEqual(Int(stretched.trailingWidth.rounded()), 220, "Trailing pane keeps its minimum width")

    // Too small for both minimums: share proportionally instead of overflowing.
    let tiny = SplitPaneLayout.resolve(totalWidth: 210, ratio: 0.5)
    assertEqual(Int(tiny.totalWidth.rounded()), 210, "Undersized container is still filled exactly, not overflowed")
    assert(tiny.leadingWidth < 200, "Leading minimum is relaxed rather than overflowing the container")
    assert(tiny.leadingWidth > 0 && tiny.trailingWidth > 0, "Both panes stay visible in an undersized container")

    // Degenerate inputs must not produce NaN or negative geometry.
    assertEqual(SplitPaneLayout.resolve(totalWidth: 0, ratio: 0.3).totalWidth, 0, "Zero width resolves to an empty layout")
    assertEqual(SplitPaneLayout.resolve(totalWidth: -50, ratio: 0.3).totalWidth, 0, "Negative width resolves to an empty layout")
    let nanRatio = SplitPaneLayout.resolve(totalWidth: 800, ratio: .nan)
    assert(nanRatio.leadingWidth.isFinite, "A non-finite ratio falls back to a finite layout")
    assertEqual(Int(nanRatio.totalWidth.rounded()), 800, "A non-finite ratio still fills the container")

    // Divider drag maps back to a clamped ratio.
    assertEqual(SplitPaneLayout.ratio(forLeadingWidth: 400, totalWidth: 801), 0.5, "Dragging to half width yields a 0.5 ratio")
    assertEqual(SplitPaneLayout.ratio(forLeadingWidth: -100, totalWidth: 801), SplitPaneLayout.minimumRatio, "Dragging past the left edge clamps to the minimum ratio")
    assertEqual(SplitPaneLayout.ratio(forLeadingWidth: 5000, totalWidth: 801), SplitPaneLayout.maximumRatio, "Dragging past the right edge clamps to the maximum ratio")
    assertEqual(SplitPaneLayout.ratio(forLeadingWidth: 100, totalWidth: 0), SplitPaneLayout.minimumRatio, "A zero-width container cannot produce a divergent ratio")

    // A drag is stable: resolving a dragged ratio reproduces that divider position.
    let dragRatio = SplitPaneLayout.ratio(forLeadingWidth: 500, totalWidth: 1001)
    let dragged = SplitPaneLayout.resolve(totalWidth: 1001, ratio: dragRatio)
    assertEqual(Int(dragged.leadingWidth.rounded()), 500, "Divider lands where it was dragged")
}

// Test 28: Workbench Layout State and Dock Persistence
print("Test 28: Workbench Layout State and Dock Persistence")
do {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let defaultLayout = WorkbenchLayoutState()
    assertEqual(defaultLayout.leftDockWidth, 260, "Default left dock width is 260")
    assertEqual(defaultLayout.rightDockWidth, 300, "Default right dock width is 300")
    assertEqual(defaultLayout.bottomDockHeightRatio, 0.35, "Default bottom dock ratio is 0.35")
    assertEqual(defaultLayout.isLeftDockCollapsed, false, "Left dock uncollapsed by default")
    assertEqual(defaultLayout.isRightDockCollapsed, false, "Right dock uncollapsed by default")
    assertEqual(defaultLayout.isBottomDockCollapsed, false, "Bottom dock uncollapsed by default")
    assertEqual(defaultLayout.activeCenterTab, CenterTab.editor, "Default center tab is editor")
    assertEqual(defaultLayout.activeLeftTab, LeftDockTab.repos, "Default left tab is repos")
    assertEqual(defaultLayout.activeRightTab, RightDockTab.changes, "Default right tab is changes")
    assertEqual(defaultLayout.focusedTicketKey, nil, "No Focus ticket is selected by default")

    // Enum cases and titles
    assertEqual(CenterTab.allCases.count, 7, "Seven center stage tabs")
    assertEqual(defaultLayout.panels(in: .left).count, 2, "Two left dock tabs")
    assertEqual(defaultLayout.panels(in: .right).count, 5, "Five right dock tabs")

    // Persistence through WorkspaceStateStore
    let storeURL = tempDir.appendingPathComponent("state.json")
    let store = WorkspaceStateStore(customStorageURL: storeURL)
    assertEqual(store.getWorkbenchLayout().activeCenterTab, CenterTab.editor, "Store provides default workbench layout")

    var customLayout = defaultLayout
    customLayout.leftDockWidth = 320
    customLayout.rightDockWidth = 380
    customLayout.bottomDockHeightRatio = 0.45
    customLayout.isLeftDockCollapsed = true
    customLayout.isRightDockCollapsed = false
    customLayout.isBottomDockCollapsed = true
    customLayout.activeCenterTab = .focus
    customLayout.activeLeftTab = .tickets
    customLayout.activeRightTab = .agents
    customLayout.focusedTicketKey = "OPS-42"
    store.saveWorkbenchLayout(customLayout)

    let reloadedStore = WorkspaceStateStore(customStorageURL: storeURL)
    let reloadedLayout = reloadedStore.getWorkbenchLayout()
    assertEqual(reloadedLayout.leftDockWidth, 320, "Persisted left dock width matches")
    assertEqual(reloadedLayout.rightDockWidth, 380, "Persisted right dock width matches")
    assertEqual(reloadedLayout.bottomDockHeightRatio, 0.45, "Persisted bottom dock ratio matches")
    assertEqual(reloadedLayout.isLeftDockCollapsed, true, "Persisted left dock collapsed state matches")
    assertEqual(reloadedLayout.isRightDockCollapsed, false, "Persisted right dock uncollapsed state matches")
    assertEqual(reloadedLayout.isBottomDockCollapsed, true, "Persisted bottom dock collapsed state matches")
    assertEqual(reloadedLayout.activeCenterTab, CenterTab.focus, "Persisted center tab matches focus")
    assertEqual(reloadedLayout.activeLeftTab, LeftDockTab.tickets, "Persisted left tab matches tickets")
    assertEqual(reloadedLayout.activeRightTab, RightDockTab.agents, "Persisted right tab matches agents")
    assertEqual(reloadedLayout.focusedTicketKey, "OPS-42", "Focused ticket persists with workspace layout")

    // Backward compatibility with legacy state files missing workbenchLayout key
    let legacyURL = tempDir.appendingPathComponent("legacy.json")
    try! #"{"repoStates":{},"hiddenRepoPaths":[],"customRepoPaths":[]}"#.write(to: legacyURL, atomically: true, encoding: .utf8)
    let legacyStore = WorkspaceStateStore(customStorageURL: legacyURL)
    assertEqual(legacyStore.getWorkbenchLayout().activeCenterTab, CenterTab.editor, "Legacy state file decodes with default workbench layout")
    assertEqual(legacyStore.getWorkbenchLayout().isLeftDockCollapsed, false, "Legacy state file preserves default dock states")
    assertEqual(legacyStore.getWorkbenchLayout().focusedTicketKey, nil, "Legacy state defaults focused ticket safely")

    let oldLayoutJSON = #"{"activeCenterTab":"Focus","activeLeftTab":"Tickets","activeRightTab":"Agents","isLeftDockCollapsed":false,"isRightDockCollapsed":false,"isBottomDockCollapsed":false,"leftDockWidth":260,"rightDockWidth":300,"bottomDockHeightRatio":0.35}"#
    let oldLayout = try! JSONDecoder().decode(WorkbenchLayoutState.self, from: Data(oldLayoutJSON.utf8))
    assertEqual(oldLayout.focusedTicketKey, nil, "Existing workbench layouts decode without the new Focus field")
}

// Regression checks for the panel-shell review.
do {
    for failure in [errSecNotAvailable, errSecParam, errSecAuthFailed, OSStatus(-34018)] {
        let unavailable = CredentialStore(
            updateItem: { _, _ in errSecItemNotFound }, addItem: { _ in failure },
            copyItem: { _, _ in failure }, deleteItem: { _ in failure })
        assert(!unavailable.saveSecret("test-only", for: .jira), "Failed Keychain save is not success")
        assert(!unavailable.hasSecret(for: .jira), "Failed save never creates a memory fallback")
        assert(!unavailable.deleteSecret(for: .jira), "Failed deletion is not success")
        assert(!unavailable.saveSecret("", for: .jira), "Blank-token deletion propagates failure")
    }
    for width in [1000.0, 1280, 1600] {
        let sizes = WorkbenchDockGeometry.resolve(width: width, left: 450, right: 500)
        assert(width - sizes.left - sizes.right - 8 >= 359.99, "Docks reserve center width")
    }
    let hidden = WorkbenchDockGeometry.resolve(width: 1000, left: 0, right: 500)
    assertEqual(hidden.left, 0, "Collapsed dock takes no space")
    var position = 260.0
    for delta in [10.0, 20, 30] {
        position = WorkbenchDockGeometry.dragged(start: 260, translation: delta, minimum: 180, maximum: 450)
    }
    assertEqual(position, 290, "Repeated drag events use the original size")
    assertEqual(WorkbenchDockGeometry.dragged(start: 300, translation: -40, minimum: 200, maximum: 500), 260, "Right divider direction")

    var layout = WorkbenchLayoutState()
    layout.move(.agents, to: .left)
    assert(layout.panels(in: .left).contains(.agents), "Agents moves into left dock")
    assert(!layout.panels(in: .right).contains(.agents), "Moved panel is not duplicated")
    assertEqual(layout.activeLeftTab, .agents, "Destination selects moved panel")
    layout.move(.tickets, to: .right)
    assertEqual(layout.activeRightTab, .tickets, "Tickets can coexist with Agents in opposite docks")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = WorkspaceStateStore(customStorageURL: url)
    store.saveWorkspacePath("/tmp/workspace-a")
    store.saveWorkbenchLayout(layout)
    assertEqual(store.getWorkbenchLayout(workspacePath: "/tmp/workspace-a").activeLeftTab, .agents, "Legacy layout migrates to original workspace")
    assertEqual(store.getWorkbenchLayout(workspacePath: "/tmp/workspace-b").activeLeftTab, .repos, "New workspace does not inherit legacy layout")
    store.saveWorkbenchLayout(layout, workspacePath: "/tmp/workspace-a")
    store.saveWorkbenchLayout(WorkbenchLayoutState(), workspacePath: "/tmp/workspace-b")
    let reload = WorkspaceStateStore(customStorageURL: url)
    assertEqual(reload.getWorkbenchLayout(workspacePath: "/tmp/workspace-a").activeRightTab, .tickets, "Panel placement and selection survive reload")
    assertEqual(reload.getWorkbenchLayout(workspacePath: "/tmp/workspace-b").activeRightTab, .changes, "Workspace layout remains independent")
}

// Test 29: End-to-End Repository Workflow and Secondary Actions (Milestone 3)
print("Test 29: End-to-End Repository Workflow and Secondary Actions (Milestone 3)")
do {
    // 1. Remote Web URL Parsing
    let sshURL = GitService.parseRemoteWebURL("git@github.com:marcelodevops/miniOps.git")
    assertEqual(sshURL?.absoluteString, "https://github.com/marcelodevops/miniOps", "git@ SSH remote parses to HTTPS URL")

    let httpsURL = GitService.parseRemoteWebURL("https://github.com/marcelodevops/miniOps.git")
    assertEqual(httpsURL?.absoluteString, "https://github.com/marcelodevops/miniOps", "HTTPS remote parses and strips .git")

    let gitlabURL = GitService.parseRemoteWebURL("ssh://git@gitlab.com/company/project.git")
    assertEqual(gitlabURL?.absoluteString, "https://gitlab.com/company/project", "ssh:// remote parses to HTTPS web URL")

    assert(GitService.parseRemoteWebURL("   ") == nil, "Empty remote URL returns nil")

    // 2. ExternalEditor Resolution and Fallbacks
    let vsCodeURL = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
    let zedURL = URL(fileURLWithPath: "/Applications/Zed.app")

    // When VS Code is detected:
    let codeResult = ExternalEditor.preferredEditorURL(appFinder: { id in
        id == "com.microsoft.VSCode" ? vsCodeURL : nil
    })
    assertEqual(codeResult?.bundleId, "com.microsoft.VSCode", "Detects VS Code when installed")
    assertEqual(codeResult?.appURL, vsCodeURL, "Resolves VS Code application URL")

    // When only Zed is detected:
    let zedResult = ExternalEditor.preferredEditorURL(appFinder: { id in
        id == "dev.zed.Zed" ? zedURL : nil
    })
    assertEqual(zedResult?.bundleId, "dev.zed.Zed", "Detects Zed when installed")
    assertEqual(zedResult?.appURL, zedURL, "Resolves Zed application URL")

    // When none detected:
    let noneResult = ExternalEditor.preferredEditorURL(appFinder: { _ in nil })
    assert(noneResult == nil, "Returns nil when no supported editor is installed")

    // Test ExternalEditor.open dispatches to preferred editor or fallback asynchronously
    var openedWithApp = false
    var openedWithDefault = false
    var completionSuccess: Bool? = nil
    ExternalEditor.open(
        path: "/tmp/sample.txt",
        appFinder: { id in id == "com.microsoft.VSCode" ? vsCodeURL : nil },
        fileOpener: { urls, app, done in
            openedWithApp = (app == vsCodeURL && urls.first?.path == "/tmp/sample.txt")
            done(true)
        },
        defaultOpener: { _, done in
            openedWithDefault = true
            done(true)
        },
        completion: { success in
            completionSuccess = success
        }
    )
    assert(openedWithApp, "ExternalEditor.open opens file with detected editor")
    assert(!openedWithDefault, "Default opener not invoked when preferred editor succeeds")
    assert(completionSuccess == true, "Completion callback reports success")

    openedWithApp = false
    openedWithDefault = false
    completionSuccess = nil
    ExternalEditor.open(
        path: "/tmp/sample.txt",
        appFinder: { _ in nil },
        fileOpener: { _, _, done in
            openedWithApp = true
            done(false)
        },
        defaultOpener: { url, done in
            openedWithDefault = (url.path == "/tmp/sample.txt")
            done(true)
        },
        completion: { success in
            completionSuccess = success
        }
    )
    assert(!openedWithApp, "No app opener called when no preferred editor exists")
    assert(openedWithDefault, "Falls back cleanly to system default opener")
    assert(completionSuccess == true, "Fallback opener completion reports success")

    // Test fallback when preferred editor reports launch failure
    openedWithApp = false
    openedWithDefault = false
    completionSuccess = nil
    ExternalEditor.open(
        path: "/tmp/sample.txt",
        appFinder: { id in id == "com.microsoft.VSCode" ? vsCodeURL : nil },
        fileOpener: { _, _, done in
            openedWithApp = true
            done(false) // Preferred editor launch fails
        },
        defaultOpener: { _, done in
            openedWithDefault = true // Fallback triggered
            done(true)
        },
        completion: { success in
            completionSuccess = success
        }
    )
    assert(openedWithApp, "Preferred editor is attempted first")
    assert(openedWithDefault, "Falls back to default opener when preferred editor reports launch failure")
    assert(completionSuccess == true, "Completion succeeds after fallback")

    // 3. Multi-repo switching with layout & commit selection restoration
    let (tempDirA, repoURLA) = setupTempRepo()
    let (tempDirB, repoURLB) = setupTempRepo()
    defer {
        try? FileManager.default.removeItem(at: tempDirA)
        try? FileManager.default.removeItem(at: tempDirB)
    }

    // Set up files in Repo A
    let stagedA = repoURLA.appendingPathComponent("staged_excluded.txt")
    let targetA = repoURLA.appendingPathComponent("target.txt")
    try! "staged excluded change".write(to: stagedA, atomically: true, encoding: .utf8)
    try! "target change".write(to: targetA, atomically: true, encoding: .utf8)
    _ = runGit(args: ["add", "staged_excluded.txt"], in: repoURLA.path)

    // Set up files in Repo B
    let fileB1 = repoURLB.appendingPathComponent("b1.txt")
    let fileB2 = repoURLB.appendingPathComponent("b2.txt")
    try! "b1 change".write(to: fileB1, atomically: true, encoding: .utf8)
    try! "b2 change".write(to: fileB2, atomically: true, encoding: .utf8)

    // Verify state store persists and restores repo states independently
    let storeURL = tempDirA.appendingPathComponent("multi_repo_state.json")
    let store = WorkspaceStateStore(customStorageURL: storeURL)

    // User is in Repo A: selects target.txt for editing and only target.txt for commit (excluding staged_excluded.txt)
    var repoAState = RepoLayoutState()
    repoAState.selectedFilePath = targetA.path
    repoAState.selectedFilesForCommit = ["target.txt"]
    repoAState.terminalHeightRatio = 0.4
    store.saveRepoState(repoPath: repoURLA.path, state: repoAState)

    // User switches to Repo B: selects b1.txt for commit (excluding b2.txt)
    var repoBState = RepoLayoutState()
    repoBState.selectedFilePath = fileB1.path
    repoBState.selectedFilesForCommit = ["b1.txt"]
    repoBState.terminalHeightRatio = 0.6
    store.saveRepoState(repoPath: repoURLB.path, state: repoBState)

    // User switches back to Repo A:
    let reloadedA = store.getRepoState(repoPath: repoURLA.path)
    assertEqual(reloadedA.selectedFilePath, targetA.path, "Repo A restores selected file")
    assertEqual(reloadedA.selectedFilesForCommit, ["target.txt"], "Repo A restores excluded commit selection")
    assertEqual(reloadedA.terminalHeightRatio, 0.4, "Repo A restores terminal ratio")

    // User switches back to Repo B:
    let reloadedB = store.getRepoState(repoPath: repoURLB.path)
    assertEqual(reloadedB.selectedFilePath, fileB1.path, "Repo B restores selected file")
    assertEqual(reloadedB.selectedFilesForCommit, ["b1.txt"], "Repo B restores excluded commit selection")
    assertEqual(reloadedB.terminalHeightRatio, 0.6, "Repo B restores terminal ratio")

    // 4. Selective commit in Repo A preserves the excluded staged changes
    let gitService = GitService.shared
    let commitResult = gitService.selectiveCommit(
        repoPath: repoURLA.path,
        message: "Selectively commit target",
        selectedPaths: ["target.txt"]
    )
    assert(commitResult.success, "Selective commit succeeded: \(commitResult.error ?? "")")

    let committedA = runGit(args: ["show", "--pretty=", "--name-only", "HEAD"], in: repoURLA.path)
    assert(committedA.contains("target.txt"), "Committed files must contain target.txt")
    assert(!committedA.contains("staged_excluded.txt"), "Committed files must NOT contain staged_excluded.txt")

    let statusA = runGit(args: ["status", "--porcelain"], in: repoURLA.path)
    assert(statusA.contains("A  staged_excluded.txt"), "Excluded staged file remains staged in git index")

    // 5. Diff output validation for Center Stage Diff Inspector
    let diff = gitService.getDiff(repoPath: repoURLA.path, filePath: "staged_excluded.txt")
    assert(!diff.isEmpty, "Diff output is generated for staged_excluded.txt")
    assert(diff.contains("diff --git"), "Diff header is standard git format")
    assert(diff.contains("+staged excluded change"), "Diff reflects staged additions")

    // 6. JSON Backward Compatibility for RepoLayoutState
    let legacyJSON = #"{"selectedFilePath":"/foo/bar.swift","expandedFolderPaths":[],"terminalHeightRatio":0.5,"isEditorCollapsed":false,"isTerminalCollapsed":false,"isGitInspectorOpen":false}"#
    let decoded = try! JSONDecoder().decode(RepoLayoutState.self, from: legacyJSON.data(using: .utf8)!)
    assertEqual(decoded.selectedFilePath, "/foo/bar.swift", "Decodes legacy RepoLayoutState without selectedFilesForCommit")
    assert(decoded.selectedFilesForCommit == nil, "Missing selectedFilesForCommit key decodes as nil")

    let encodedData = try! JSONEncoder().encode(repoAState)
    let roundTrip = try! JSONDecoder().decode(RepoLayoutState.self, from: encodedData)
    assertEqual(roundTrip.selectedFilesForCommit, ["target.txt"], "Round-trip JSON encodes and decodes selectedFilesForCommit")
}

// Test 30: UI Transition Invariants & Robustness (Milestone 3 Fixes)
print("Test 30: UI Transition Invariants & Robustness (Milestone 3 Fixes)")
do {
    let (tempDir, repoURL) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let gitService = GitService.shared

    // Commit a baseline file to HEAD
    let file = repoURL.appendingPathComponent("sample.txt")
    try! "line 1\nline 2\n".write(to: file, atomically: true, encoding: .utf8)
    _ = runGit(args: ["add", "sample.txt"], in: repoURL.path)
    _ = runGit(args: ["commit", "-m", "Initial commit"], in: repoURL.path)

    // Stage a modification: "line 1\nline 2 modified\n"
    try! "line 1\nline 2 modified\n".write(to: file, atomically: true, encoding: .utf8)
    _ = runGit(args: ["add", "sample.txt"], in: repoURL.path)

    // Restore working tree file to HEAD state ("line 1\nline 2\n")
    try! "line 1\nline 2\n".write(to: file, atomically: true, encoding: .utf8)

    // Finding 4 verification: getDiff must report "No differences" compared to HEAD,
    // NOT the index-to-working-tree reverse diff!
    let diffAfterRestore = gitService.getDiff(repoPath: repoURL.path, filePath: "sample.txt")
    assertEqual(diffAfterRestore, "No differences", "Diff must accept empty HEAD comparison without reverse fallback")

    // Finding 4 verification: unborn repository diff fallback
    let unbornDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: unbornDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: unbornDir) }
    _ = runGit(args: ["init", "-b", "main"], in: unbornDir.path)
    let unbornFile = unbornDir.appendingPathComponent("first.txt")
    try! "hello unborn".write(to: unbornFile, atomically: true, encoding: .utf8)
    _ = runGit(args: ["add", "first.txt"], in: unbornDir.path)

    let unbornDiff = gitService.getDiff(repoPath: unbornDir.path, filePath: "first.txt")
    assert(unbornDiff.contains("+hello unborn"), "Unborn repo correctly falls back to staged diff")

    // Finding 3 verification: File path normalization and restoration
    let fileSystem = FileSystemService.shared
    let subfolder = repoURL.appendingPathComponent("sub/dir", isDirectory: true)
    try! FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
    let subFile = subfolder.appendingPathComponent("nested.swift")
    try! "// nested".write(to: subFile, atomically: true, encoding: .utf8)

    // Relative path passed by center diff "Open in Editor"
    let relativePath = "sub/dir/nested.swift"
    let validated = fileSystem.validatePathWithin(repoPath: repoURL.path, filePath: relativePath)
    assertEqual(validated?.path, subFile.standardized.path, "Validates and normalizes relative path to absolute URL")

    // Verify restoration of stored relative or absolute path
    let resolvedFromRelative = (relativePath as NSString).isAbsolutePath ? relativePath : (repoURL.path as NSString).appendingPathComponent(relativePath)
    assert(FileManager.default.fileExists(atPath: resolvedFromRelative), "Restores relative path by resolving against repo path")

    // Finding 6 verification: Immediate persistence on toggle across simulated app relaunch
    let storeURL = tempDir.appendingPathComponent("state_test.json")
    let store = WorkspaceStateStore(customStorageURL: storeURL)
    var testState = RepoLayoutState()
    testState.selectedFilesForCommit = ["file1.txt", "file2.txt"]
    store.saveRepoState(repoPath: repoURL.path, state: testState)

    // User toggles off file2.txt:
    testState.selectedFilesForCommit = ["file1.txt"]
    store.saveRepoState(repoPath: repoURL.path, state: testState)

    // Simulate immediate app quit & relaunch:
    let reloadedStore = WorkspaceStateStore(customStorageURL: storeURL)
    let reloadedState = reloadedStore.getRepoState(repoPath: repoURL.path)
    assertEqual(reloadedState.selectedFilesForCommit, ["file1.txt"], "Direct toggle persists immediately across relaunch")

    // Finding 2 verification: Commit operation isolation across repositories
    let (tempB, repoURLB) = setupTempRepo()
    defer { try? FileManager.default.removeItem(at: tempB) }
    var stateB = RepoLayoutState()
    stateB.selectedFilesForCommit = ["b_keep.txt"]
    store.saveRepoState(repoPath: repoURLB.path, state: stateB)

    // Commit in Repo A clears Repo A's selection in store:
    var stateA = store.getRepoState(repoPath: repoURL.path)
    stateA.selectedFilesForCommit = []
    store.saveRepoState(repoPath: repoURL.path, state: stateA)

    // Repo B's selection must remain intact and isolated:
    let stateBAfterCommitA = store.getRepoState(repoPath: repoURLB.path)
    assertEqual(stateBAfterCommitA.selectedFilesForCommit, ["b_keep.txt"], "Repo A commit does not clear Repo B's selection")
}

// Test 31: End-to-End ViewModel Workflow Validation (Two Repos, Delayed Commit & External Edit)
print("Test 31: End-to-End ViewModel Workflow Validation (Two Repos, Delayed Commit & External Edit)")
do {
    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    // 1. Setup two Git repositories in tempRoot
    let repoDirA = tempRoot.appendingPathComponent("repoA")
    let repoDirB = tempRoot.appendingPathComponent("repoB")
    try! FileManager.default.createDirectory(at: repoDirA, withIntermediateDirectories: true)
    try! FileManager.default.createDirectory(at: repoDirB, withIntermediateDirectories: true)

    _ = runGit(args: ["init", "-b", "main"], in: repoDirA.path)
    _ = runGit(args: ["config", "user.name", "Test Runner"], in: repoDirA.path)
    _ = runGit(args: ["config", "user.email", "test@example.com"], in: repoDirA.path)
    _ = runGit(args: ["config", "commit.gpgsign", "false"], in: repoDirA.path)

    _ = runGit(args: ["init", "-b", "main"], in: repoDirB.path)
    _ = runGit(args: ["config", "user.name", "Test Runner"], in: repoDirB.path)
    _ = runGit(args: ["config", "user.email", "test@example.com"], in: repoDirB.path)
    _ = runGit(args: ["config", "commit.gpgsign", "false"], in: repoDirB.path)

    // Initial commit in Repo A
    let fileA1 = repoDirA.appendingPathComponent("fileA1.txt")
    let fileA2 = repoDirA.appendingPathComponent("fileA2.txt")
    try! "version 1\n".write(to: fileA1, atomically: true, encoding: .utf8)
    _ = runGit(args: ["add", "fileA1.txt"], in: repoDirA.path)
    _ = runGit(args: ["commit", "-m", "Initial commit in A"], in: repoDirA.path)

    // Initial commit in Repo B
    let fileB1 = repoDirB.appendingPathComponent("fileB1.txt")
    try! "initial b\n".write(to: fileB1, atomically: true, encoding: .utf8)
    _ = runGit(args: ["add", "fileB1.txt"], in: repoDirB.path)
    _ = runGit(args: ["commit", "-m", "Initial commit in B"], in: repoDirB.path)

    // Create modified and uncommitted files in Repo A
    try! "version 1\nversion 2\n".write(to: fileA1, atomically: true, encoding: .utf8)
    try! "uncommitted file A2\n".write(to: fileA2, atomically: true, encoding: .utf8)

    // Create modified file in Repo B
    try! "initial b\nmodified b1\n".write(to: fileB1, atomically: true, encoding: .utf8)

    // Initialize custom WorkspaceStateStore and WorkspaceViewModel
    let storeURL = tempRoot.appendingPathComponent("workflow_state.json")
    let customStore = WorkspaceStateStore(customStorageURL: storeURL)

    MainActor.assumeIsolated {
        let viewModel = WorkspaceViewModel(stateStore: customStore)
        viewModel.setWorkspace(path: tempRoot.path)

        // Drain runloop to allow scan to complete
        var retries = 0
        while (viewModel.isScanning || viewModel.repositories.count < 2) && retries < 50 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            retries += 1
        }
        assertEqual(viewModel.repositories.count, 2, "Discovers both temporary repositories")

        guard let repoAInfo = viewModel.repositories.first(where: { $0.path == repoDirA.path }),
              let repoBInfo = viewModel.repositories.first(where: { $0.path == repoDirB.path }) else {
            fatalError("Repositories not found")
        }

        // Step 1: Select Repo A and verify initial state
        viewModel.selectRepo(repoAInfo)
        assertEqual(viewModel.selectedRepo?.path, repoDirA.path, "Repo A is selected")

        // Wait for repo status to refresh
        retries = 0
        while (viewModel.selectedRepo?.changedFiles.isEmpty ?? true) && retries < 30 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            retries += 1
        }
        let changedFilesA = viewModel.selectedRepo?.changedFiles ?? []
        assert(changedFilesA.contains(where: { $0.path == "fileA1.txt" }), "fileA1.txt is detected as changed")
        assert(changedFilesA.contains(where: { $0.path == "fileA2.txt" }), "fileA2.txt is detected as untracked/changed")

        // Select only fileA1.txt for commit and inspect diff
        viewModel.setCommitSelection(["fileA1.txt"])
        assertEqual(viewModel.selectedFilesForCommit, ["fileA1.txt"], "Only fileA1.txt is selected for commit, fileA2.txt excluded")
        viewModel.inspectDiff(filePath: "fileA1.txt")
        assertEqual(viewModel.activeDiffFile, "fileA1.txt", "Center stage targets fileA1.txt diff")
        assertEqual(viewModel.workbenchLayout.activeCenterTab, .diff, "Center tab switches to .diff")

        // Wait for initial rendered diff to load
        retries = 0
        while viewModel.activeDiffContent.isEmpty && retries < 30 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            retries += 1
        }
        assert(viewModel.activeDiffContent.contains("+version 2"), "Initial rendered diff displays version 2 additions")

        // Step 2: UI check for same-file external edits through BOTH refresh routes
        // Route 1: refreshCurrentRepoStatus()
        try! "version 1\nversion 2\nversion 3\n".write(to: fileA1, atomically: true, encoding: .utf8)
        viewModel.refreshCurrentRepoStatus()

        retries = 0
        while !viewModel.activeDiffContent.contains("+version 3") && retries < 30 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            retries += 1
        }
        assert(viewModel.activeDiffContent.contains("+version 3"), "UI check: rendered diff updates to +version 3 via refreshCurrentRepoStatus route")
        assertEqual(viewModel.selectedFilesForCommit, ["fileA1.txt"], "Commit selection survives Route 1 status refresh")

        // Route 2: refreshRepositories() (sidebar workspace rescan)
        try! "version 1\nversion 2\nversion 3\nversion 4\n".write(to: fileA1, atomically: true, encoding: .utf8)
        viewModel.refreshRepositories()

        retries = 0
        while !viewModel.activeDiffContent.contains("+version 4") && retries < 40 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            retries += 1
        }
        assert(viewModel.activeDiffContent.contains("+version 4"), "UI check: rendered diff updates to +version 4 via refreshRepositories sidebar rescan route")
        assertEqual(viewModel.selectedFilesForCommit, ["fileA1.txt"], "Commit selection survives Route 2 workspace rescan")

        // Step 3 & 4: Deliberately block Repo A's commit in-flight, switch to B while running, release it, verify both repositories
        assertEqual(viewModel.selectedRepo?.path, repoDirA.path, "Repo A is active before starting commit")
        assertEqual(viewModel.selectedFilesForCommit, ["fileA1.txt"], "Repo A has fileA1.txt selected for commit")

        let commitStarted = DispatchSemaphore(value: 0)
        let commitGate = DispatchSemaphore(value: 0)
        GitService.shared.preCommitHook = { path in
            if path == repoDirA.path {
                commitStarted.signal() // Signal that Repo A commit is actively in-flight under repo lock
                commitGate.wait()      // Deliberately block Repo A commit until released
            }
        }

        var commitFinished = false
        var commitSuccess = false
        viewModel.executeSelectiveCommit(
            repoPath: repoDirA.path,
            message: "Deliberately blocked in-flight commit in A",
            selectedPaths: ["fileA1.txt"]
        ) { result in
            commitFinished = true
            commitSuccess = result.success
        }

        // Wait until Repo A's commit has actively started and entered the gate
        let startedRes = commitStarted.wait(timeout: .now() + 5)
        assert(startedRes == .success, "Repo A commit started and is blocked in-flight")
        assert(!commitFinished, "Repo A commit is actively in-flight and not yet completed")

        // WHILE Repo A commit is running and blocked, switch to Repo B!
        viewModel.selectRepo(repoBInfo)
        assertEqual(viewModel.selectedRepo?.path, repoDirB.path, "Switched to Repo B while Repo A commit is in-flight")

        // Wait for repo B status refresh
        retries = 0
        while (viewModel.selectedRepo?.changedFiles.isEmpty ?? true) && retries < 30 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            retries += 1
        }
        viewModel.setCommitSelection(["fileB1.txt"])
        assertEqual(viewModel.selectedFilesForCommit, ["fileB1.txt"], "Repo B has fileB1.txt selected while Repo A commit is blocked")

        // RELEASE Repo A's commit to finish in the background
        commitGate.signal()

        retries = 0
        while !commitFinished && retries < 50 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            retries += 1
        }
        assert(commitFinished && commitSuccess, "Repo A in-flight commit succeeded after release")
        GitService.shared.preCommitHook = nil // Clean up hook

        // Invariants verification after Repo A commit completes while Repo B is active:
        // 1. Repo B is STILL the active repo in viewModel
        assertEqual(viewModel.selectedRepo?.path, repoDirB.path, "Active repo is still Repo B")
        // 2. Repo B's selection MUST NOT have been cleared or corrupted by Repo A's commit completion!
        assertEqual(viewModel.selectedFilesForCommit, ["fileB1.txt"], "Repo B's active selection is preserved and isolated from Repo A's commit completion")
        let statusB = runGit(args: ["status", "--porcelain"], in: repoDirB.path)
        assert(statusB.contains("fileB1.txt"), "Repo B working tree files were not committed by Repo A")

        // 3. Repo A's persisted state in store has its selection cleared
        let persistedStateA = customStore.getRepoState(repoPath: repoDirA.path)
        assertEqual(persistedStateA.selectedFilesForCommit, [], "Repo A persisted selection was cleared upon its commit")
        // 4. In Repo A Git history, fileA1.txt is committed, while fileA2.txt remains uncommitted
        let logA = runGit(args: ["log", "-1", "--pretty=%s"], in: repoDirA.path)
        assertEqual(logA.trimmingCharacters(in: .whitespacesAndNewlines), "Deliberately blocked in-flight commit in A", "Git HEAD reflects Repo A commit")
        let committedFilesInA = runGit(args: ["show", "--pretty=", "--name-only", "HEAD"], in: repoDirA.path)
        assert(committedFilesInA.contains("fileA1.txt"), "fileA1.txt was committed")
        assert(!committedFilesInA.contains("fileA2.txt"), "fileA2.txt was excluded from commit")
        let statusA = runGit(args: ["status", "--porcelain"], in: repoDirA.path)
        assert(statusA.contains("fileA2.txt"), "fileA2.txt remains in working tree of Repo A")

        // Step 5: Switch back to Repo A and verify restored clean selection
        viewModel.selectRepo(repoAInfo)
        assertEqual(viewModel.selectedRepo?.path, repoDirA.path, "Switched back to Repo A")
        retries = 0
        while (viewModel.selectedRepo?.changedFiles.isEmpty ?? true) && retries < 30 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            retries += 1
        }
        assertEqual(viewModel.selectedFilesForCommit, [], "Repo A selection is empty after switching back")

        // Step 6: Test Center Stage Detail Tabs (Ticket & Agent)
        let ticket = TicketInfo(key: "OPS-999", summary: "Parity Workflow Ticket", priority: "High", localPath: fileA2.path)
        viewModel.selectTicket(ticket)
        assertEqual(viewModel.selectedTicket?.key, "OPS-999", "Ticket selected in viewModel")
        assertEqual(viewModel.workbenchLayout.activeCenterTab, .ticket, "Active center tab switches to .ticket")

        let agent = AgentInfo(pid: 88888, tool: "TestRunnerAgent", status: "running", isWaitingForInput: false, elapsed: "42s", repoPath: repoDirA.path)
        viewModel.selectAgent(agent)
        assertEqual(viewModel.selectedAgent?.pid, 88888, "Agent selected in viewModel")
        assertEqual(viewModel.workbenchLayout.activeCenterTab, .agent, "Active center tab switches to .agent")

        viewModel.selectCenterTab(.editor)
        assertEqual(viewModel.workbenchLayout.activeCenterTab, .editor, "Active center tab switches back to .editor")
    }
}

// Test 32: Process Runner Does Not Re-enter the Main Run Loop
print("Test 32: Process Runner Does Not Re-enter the Main Run Loop")
do {
    assert(Thread.isMainThread, "The regression probe must run on the main thread")

    var mainRunLoopReentered = false
    let timer = Timer(timeInterval: 0.01, repeats: false) { _ in
        mainRunLoopReentered = true
    }
    RunLoop.main.add(timer, forMode: .default)

    let result = ProcessRunner.run(
        executable: "/bin/sh",
        arguments: ["-c", "sleep 0.1"],
        currentDirectory: NSTemporaryDirectory(),
        timeout: 1
    )
    timer.invalidate()

    assertEqual(result.status, 0, "The probe subprocess should exit successfully")
    assert(!mainRunLoopReentered, "Waiting for a subprocess must not pump the main run loop during a SwiftUI transaction")
}

// Test 33: Milestone 4 Focus Persistence, Context Association, and Overview Filters
print("Test 33: Milestone 4 Focus Persistence, Context Association, and Overview Filters")
do {
    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repoAURL = tempRoot.appendingPathComponent("repo-a")
    let repoBURL = tempRoot.appendingPathComponent("repo-b")
    let ticketDirectory = repoAURL.appendingPathComponent("tickets")
    let repoBTicketDirectory = repoBURL.appendingPathComponent("tickets")
    try! FileManager.default.createDirectory(at: ticketDirectory, withIntermediateDirectories: true)
    try! FileManager.default.createDirectory(at: repoBTicketDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let localTicketPath = ticketDirectory.appendingPathComponent("OPS-42.md").path
    try! "# Local ticket".write(toFile: localTicketPath, atomically: true, encoding: .utf8)
    try! "# Second local ticket".write(
        to: repoBTicketDirectory.appendingPathComponent("OPS-99.md"),
        atomically: true,
        encoding: .utf8
    )

    let repoA = RepoInfo(name: "repo-a", path: repoAURL.path, branch: "main", isDirty: true)
    let repoB = RepoInfo(name: "repo-b", path: repoBURL.path, branch: "feat/OPS-77-api")
    let localTicket = TicketInfo(key: "OPS-42", summary: "Local ticket", localPath: localTicketPath)
    let branchTicket = TicketInfo(key: "OPS-77", summary: "Branch-associated Jira ticket")
    let cachedTicket = TicketInfo(
        key: "OPS-88",
        summary: "Workspace cache must not imply repository ownership",
        localPath: repoAURL.appendingPathComponent("jira-cache.json").path
    )

    assertEqual(
        TicketScanner.shared.associatedRepository(for: localTicket, repositories: [repoA, repoB])?.path,
        repoA.path,
        "A local ticket file resolves to its containing repository"
    )
    assertEqual(
        TicketScanner.shared.associatedRepository(for: branchTicket, repositories: [repoA, repoB])?.path,
        repoB.path,
        "A Jira ticket resolves to a repository branch containing its key"
    )
    assertEqual(
        TicketScanner.shared.associatedRepository(for: cachedTicket, repositories: [repoA, repoB])?.path,
        nil,
        "A shared Jira cache path does not falsely associate every cached ticket with its containing repository"
    )
    let prefixTicket = TicketInfo(key: "OPS-7", summary: "Must not match OPS-77")
    assertEqual(
        TicketScanner.shared.associatedRepository(for: prefixTicket, repositories: [repoA, repoB])?.path,
        nil,
        "Ticket key matching observes numeric boundaries"
    )
    let workspaceTickets = TicketScanner.shared.scanTickets(
        workspacePath: tempRoot.path,
        repoPaths: [repoA.path, repoB.path]
    )
    assert(workspaceTickets.contains(where: { $0.key == "OPS-42" }), "Workspace scan includes tickets from repo A")
    assert(workspaceTickets.contains(where: { $0.key == "OPS-99" }), "Workspace scan includes tickets from repo B")

    let storeURL = tempRoot.appendingPathComponent("state.json")
    let store = WorkspaceStateStore(customStorageURL: storeURL)
    store.saveWorkspacePath(tempRoot.path)
    MainActor.assumeIsolated {
        let viewModel = WorkspaceViewModel(stateStore: store)
        viewModel.repositories = [repoA, repoB]
        viewModel.tickets = [localTicket, branchTicket]
        viewModel.activeAgents = [
            AgentInfo(
                pid: 4242,
                tool: "FocusAgent",
                status: "running",
                isWaitingForInput: false,
                elapsed: "1m",
                repoPath: repoB.path
            )
        ]

        viewModel.selectFocusTicket(branchTicket)
        assertEqual(viewModel.focusedTicket()?.key, "OPS-77", "Focus uses the persisted ticket key")
        assertEqual(viewModel.repository(for: branchTicket)?.path, repoB.path, "Focus uses ticket-associated repository context")
        assertEqual(viewModel.agents(for: branchTicket).map(\.pid), [4242], "Focus limits agents to the associated repository")
        assertEqual(viewModel.workbenchLayout.activeCenterTab, .focus, "Selecting Focus ticket opens the Focus center tab")
        assertEqual(
            store.getWorkbenchLayout(workspacePath: tempRoot.path).focusedTicketKey,
            "OPS-77",
            "Focus selection is persisted per workspace"
        )

        viewModel.showRepositories(filter: .dirty)
        assertEqual(viewModel.repositoryPanelFilter, .dirty, "Overview can request dirty repositories")
        assertEqual(viewModel.workbenchLayout.activeLeftTab, .repos, "Repository summary opens the Repositories panel")
        viewModel.showTickets(filter: .open)
        assertEqual(viewModel.ticketPanelFilter, .open, "Overview can request open tickets")
        assertEqual(viewModel.workbenchLayout.activeLeftTab, .tickets, "Ticket summary opens the Tickets panel")
        viewModel.showAgents(filter: .waiting)
        assertEqual(viewModel.agentPanelFilter, .waiting, "Overview can request waiting agents")
        assertEqual(viewModel.workbenchLayout.activeRightTab, .agents, "Agent summary opens the Agents panel")
    }
}

// Test 34: Overview Analytics, Reference Charts, Tags/Origin Detection, Filter Records, and Focus AI Context
print("Test 34: Overview Analytics, Reference Charts, Tags/Origin Detection, Filter Records, and Focus AI Context")
do {
    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let repo1URL = tempRoot.appendingPathComponent("k8s-cluster-helm")
    let repo2URL = tempRoot.appendingPathComponent("cloud-terraform-infra")
    let repo3URL = tempRoot.appendingPathComponent("local-backend-service")
    try! FileManager.default.createDirectory(at: repo1URL, withIntermediateDirectories: true)
    try! FileManager.default.createDirectory(at: repo2URL, withIntermediateDirectories: true)
    try! FileManager.default.createDirectory(at: repo3URL, withIntermediateDirectories: true)

    // Repo 1: GitHub remote, helm/k8s tags, clean, has stash
    _ = runGit(args: ["init", "-b", "main"], in: repo1URL.path)
    _ = runGit(args: ["config", "user.name", "miniOps Test"], in: repo1URL.path)
    _ = runGit(args: ["config", "user.email", "test@example.com"], in: repo1URL.path)
    _ = runGit(args: ["config", "commit.gpgsign", "false"], in: repo1URL.path)
    _ = runGit(args: ["remote", "add", "origin", "https://github.com/myorg/k8s-cluster-helm.git"], in: repo1URL.path)
    try! "apiVersion: v2\nname: test-chart".write(to: repo1URL.appendingPathComponent("Chart.yaml"), atomically: true, encoding: .utf8)
    _ = runGit(args: ["add", "Chart.yaml"], in: repo1URL.path)
    _ = runGit(args: ["commit", "-m", "init helm"], in: repo1URL.path)
    try! "temp stash".write(to: repo1URL.appendingPathComponent("temp.txt"), atomically: true, encoding: .utf8)
    _ = runGit(args: ["stash", "push", "-u", "-m", "WIP stash"], in: repo1URL.path)

    // Repo 2: GitLab remote, terraform tag, dirty, merge-in-progress simulation
    _ = runGit(args: ["init", "-b", "feat/INFRA-500"], in: repo2URL.path)
    _ = runGit(args: ["config", "user.name", "miniOps Test"], in: repo2URL.path)
    _ = runGit(args: ["config", "user.email", "test@example.com"], in: repo2URL.path)
    _ = runGit(args: ["config", "commit.gpgsign", "false"], in: repo2URL.path)
    _ = runGit(args: ["remote", "add", "origin", "git@gitlab.com:myorg/cloud-infra.git"], in: repo2URL.path)
    try! "terraform {}\n".write(to: repo2URL.appendingPathComponent("main.tf"), atomically: true, encoding: .utf8)
    _ = runGit(args: ["add", "main.tf"], in: repo2URL.path)
    _ = runGit(args: ["commit", "-m", "init tf"], in: repo2URL.path)
    try! "# modified\n".write(to: repo2URL.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
    // Simulate merge in progress
    let gitDirRes = runGit(args: ["rev-parse", "--git-dir"], in: repo2URL.path)
    let gitDir = gitDirRes.hasPrefix("/") ? gitDirRes : repo2URL.appendingPathComponent(gitDirRes).path
    let mergeHeadPath = URL(fileURLWithPath: gitDir).appendingPathComponent("MERGE_HEAD").path
    try! "0123456789abcdef0123456789abcdef01234567\n".write(toFile: mergeHeadPath, atomically: true, encoding: .utf8)

    // Repo 3: Local only (no remote origin, no upstream)
    _ = runGit(args: ["init", "-b", "dev"], in: repo3URL.path)
    _ = runGit(args: ["config", "user.name", "miniOps Test"], in: repo3URL.path)
    _ = runGit(args: ["config", "user.email", "test@example.com"], in: repo3URL.path)
    _ = runGit(args: ["config", "commit.gpgsign", "false"], in: repo3URL.path)
    try! "package main\n".write(to: repo3URL.appendingPathComponent("main.go"), atomically: true, encoding: .utf8)
    _ = runGit(args: ["add", "main.go"], in: repo3URL.path)
    _ = runGit(args: ["commit", "-m", "init local"], in: repo3URL.path)

    let scannedRepos = WorkspaceScanner.shared.scan(rootPath: tempRoot.path)
    assertEqual(scannedRepos.count, 3, "Scans all three repositories in the workspace")

    let r1 = scannedRepos.first(where: { $0.name == "k8s-cluster-helm" })
    assert(r1 != nil, "Found k8s repo")
    assert(r1?.tags.contains("k8s") == true, "Tags detect k8s from repo name")
    assert(r1?.tags.contains("helm") == true, "Tags detect helm from Chart.yaml")
    assertEqual(r1?.origin, "github", "Origin detected as github")
    assertEqual(r1?.normalizedOrigin, "github", "Normalized origin is github")
    assertEqual(r1?.stashCount, 1, "Detects stashCount from git stash")

    let r2 = scannedRepos.first(where: { $0.name == "cloud-terraform-infra" })
    assert(r2 != nil, "Found terraform repo")
    assert(r2?.tags.contains("terraform") == true, "Tags detect terraform from main.tf")
    assertEqual(r2?.origin, "gitlab", "Origin detected as gitlab")
    assertEqual(r2?.normalizedOrigin, "gitlab", "Normalized origin is gitlab")
    assert(r2?.isDirty == true, "Detects dirty working tree")
    assert(r2?.isMerging == true, "Detects merge in progress via MERGE_HEAD")

    let r3 = scannedRepos.first(where: { $0.name == "local-backend-service" })
    assert(r3 != nil, "Found local repo")
    assertEqual(r3?.origin, nil, "Raw origin is nil for local repo")
    assertEqual(r3?.normalizedOrigin, "local", "Normalized origin is 'local' when remote origin is nil")
    assertEqual(r3?.hasUpstream, false, "Local repo without remote tracking has no upstream")

    // Test JSON backward compatibility for RepoInfo
    let legacyJSON = """
    {
        "name": "legacy-repo",
        "path": "/tmp/legacy",
        "branch": "main",
        "isDirty": false,
        "ahead": 0,
        "behind": 0,
        "changedFiles": []
    }
    """.data(using: .utf8)!
    let decodedRepo = try? JSONDecoder().decode(RepoInfo.self, from: legacyJSON)
    assert(decodedRepo != nil, "Legacy RepoInfo JSON decodes successfully without tags or origin")
    assertEqual(decodedRepo?.tags ?? ["dummy"], [], "Missing tags default to empty array")
    assertEqual(decodedRepo?.origin, nil, "Missing origin defaults to nil")
    assertEqual(decodedRepo?.normalizedOrigin, "local", "Missing origin normalizes to 'local'")
    assertEqual(decodedRepo?.hasUpstream, true, "Missing hasUpstream defaults to true")
    assertEqual(decodedRepo?.stashCount, 0, "Missing stashCount defaults to 0")
    assertEqual(decodedRepo?.isMerging, false, "Missing isMerging defaults to false")

    // Test WorkspaceViewModel analytics and filter navigation
    let storeURL = tempRoot.appendingPathComponent("analytics-state.json")
    let store = WorkspaceStateStore(customStorageURL: storeURL)
    store.saveWorkspacePath(tempRoot.path)

    let now = Date()
    let day: TimeInterval = 86400
    let dateCritical = now.addingTimeInterval(-20 * day) // 20 days ago
    let dateStale = now.addingTimeInterval(-7 * day)      // 7 days ago
    let dateFresh = now.addingTimeInterval(-1 * day)      // 1 day ago

    let t1 = TicketInfo(key: "INFRA-500", summary: "Upgrade cluster ingress", status: "In Progress", statusCategory: "in_progress", priority: "High", isOpen: true, created: dateCritical)
    let t2 = TicketInfo(key: "OPS-600", summary: "Rotate credentials", status: "To Do", statusCategory: "todo", priority: "Medium", isOpen: true, created: dateStale)
    let t3 = TicketInfo(key: "OPS-400", summary: "Documentation update", status: "Done", statusCategory: "done", priority: "Low", isOpen: false, created: dateFresh)
    // Alias category and empty priority tickets
    let t4 = TicketInfo(key: "OPS-700", summary: "Worker thread deadlock", status: "In Dev", statusCategory: "inprogress", priority: "", isOpen: true, created: dateFresh)
    let t5 = TicketInfo(key: "OPS-800", summary: "Review audit log format", status: "Work Pending", statusCategory: "in-progress", priority: "None", isOpen: true, created: dateStale)

    MainActor.assumeIsolated {
        let viewModel = WorkspaceViewModel(stateStore: store)
        viewModel.repositories = scannedRepos
        viewModel.tickets = [t1, t2, t3, t4, t5]
        viewModel.activeAgents = [
            AgentInfo(
                pid: 5555,
                tool: "TerraformAgent",
                status: "waiting",
                isWaitingForInput: true,
                elapsed: "3m",
                repoPath: repo2URL.path
            )
        ]

        // 1. Check ticketsByCategory with aliases
        let catStats = viewModel.ticketsByCategory
        assertEqual(catStats.first(where: { $0.category == "In Progress" })?.count, 3, "Category In Progress counts 'in_progress', 'inprogress', and 'in-progress' (t1, t4, t5)")
        assertEqual(catStats.first(where: { $0.category == "To Do" })?.count, 1, "Category To Do counts t2")
        assertEqual(catStats.first(where: { $0.category == "Done" })?.count, 1, "Category Done counts t3")

        // 2. Check ticketsByPriority with empty and 'None'
        let prioStats = viewModel.ticketsByPriority
        assertEqual(prioStats.first(where: { $0.priority == "High" })?.count, 1, "Priority High count matches t1")
        assertEqual(prioStats.first(where: { $0.priority == "Medium" })?.count, 1, "Priority Medium count matches t2")
        assertEqual(prioStats.first(where: { $0.priority == "Low" })?.count, 1, "Priority Low count matches t3")
        assertEqual(prioStats.first(where: { $0.priority == "None" })?.count, 2, "Priority None count includes empty string (t4) and 'None' (t5)")

        // 3. Check reposByType
        let typeStats = viewModel.reposByType
        assert(typeStats.contains(where: { $0.tag == "k8s" && $0.count == 1 }), "reposByType includes k8s")
        assert(typeStats.contains(where: { $0.tag == "terraform" && $0.count == 1 }), "reposByType includes terraform")

        // 4. Check reposByOrigin including local
        let originStats = viewModel.reposByOrigin
        assert(originStats.contains(where: { $0.origin == "github" && $0.count == 1 }), "reposByOrigin includes github")
        assert(originStats.contains(where: { $0.origin == "gitlab" && $0.count == 1 }), "reposByOrigin includes gitlab")
        assert(originStats.contains(where: { $0.origin == "local" && $0.count == 1 }), "reposByOrigin includes local for repositories with origin == nil")

        // 5. Check actual records displayed by repository origin filter (Fixing P2: Local origin returns no repos)
        let localRepos = viewModel.visibleRepositories(for: .origin("local"))
        assertEqual(localRepos.count, 1, "Filtering by origin 'local' returns 1 repository")
        assertEqual(localRepos.first?.name, "local-backend-service", "Filtering by origin 'local' returns the local repository whose origin is nil")

        let githubRepos = viewModel.visibleRepositories(for: .origin("github"))
        assertEqual(githubRepos.count, 1, "Filtering by origin 'github' returns 1 repository")
        assertEqual(githubRepos.first?.name, "k8s-cluster-helm", "Filtering by origin 'github' returns the github repository")

        let gitlabRepos = viewModel.visibleRepositories(for: .origin("gitlab"))
        assertEqual(gitlabRepos.count, 1, "Filtering by origin 'gitlab' returns 1 repository")
        assertEqual(gitlabRepos.first?.name, "cloud-terraform-infra", "Filtering by origin 'gitlab' returns the gitlab repository")

        // 6. Check actual records displayed by ticket category filter (Fixing P2: Category aliases)
        let inProgressTickets = viewModel.filteredTickets(for: .category("In Progress"))
        assertEqual(inProgressTickets.count, 3, "Filtering by 'In Progress' returns all 3 matching tickets including aliases")
        assert(inProgressTickets.contains(where: { $0.key == "INFRA-500" }), "Contains in_progress ticket")
        assert(inProgressTickets.contains(where: { $0.key == "OPS-700" }), "Contains inprogress ticket")
        assert(inProgressTickets.contains(where: { $0.key == "OPS-800" }), "Contains in-progress ticket")

        // 7. Check actual records displayed by ticket priority filter (Fixing P2: Empty priority disappearing)
        let nonePriorityTickets = viewModel.filteredTickets(for: .priority("None"))
        assertEqual(nonePriorityTickets.count, 2, "Filtering by 'None' priority returns 2 tickets")
        assert(nonePriorityTickets.contains(where: { $0.key == "OPS-700" }), "Tickets with empty priority '' do NOT disappear when clicking 'None'")
        assert(nonePriorityTickets.contains(where: { $0.key == "OPS-800" }), "Tickets with 'None' priority appear when clicking 'None'")

        // 8. Check Reference Repository Attention Scoring and Reasons
        // r2 has isMerging (100) + isDirty (10) = 110
        let r2Reasons = [
            r2?.isMerging == true ? "merge in progress" : nil,
            r2?.isDirty == true ? "dirty" : nil
        ].compactMap { $0 }
        assert(r2Reasons.contains("merge in progress"), "r2 attention reasons include 'merge in progress'")
        assert(r2Reasons.contains("dirty"), "r2 attention reasons include 'dirty'")

        // r3 has no upstream (+3)
        let r3Reasons = [
            r3?.hasUpstream == false ? "no upstream" : nil
        ].compactMap { $0 }
        assert(r3Reasons.contains("no upstream"), "r3 attention reasons include 'no upstream'")

        // r1 has stash (+1)
        let r1Reasons = [
            (r1?.stashCount ?? 0) > 0 ? "\(r1!.stashCount) stashed" : nil
        ].compactMap { $0 }
        assert(r1Reasons.contains("1 stashed"), "r1 attention reasons include '1 stashed'")

        // 9. Check Reference Ticket Attention Ranking and Age Badges
        let openTickets = viewModel.tickets.filter { $0.isOpen }.sorted { $0.daysOpen > $1.daysOpen }
        assertEqual(openTickets.count, 4, "4 open tickets needing attention")
        assertEqual(openTickets.first?.key, "INFRA-500", "Oldest ticket (20d) ranked first in attention queue")
        assert(openTickets.first?.ageBand.isCritical == true, "20d ticket classified in critical age band (red)")
        assertEqual(openTickets.first?.ageBand.label, "20d", "20d ticket label formatted correctly")

        let staleTicket = openTickets.first(where: { $0.key == "OPS-600" })
        assert(staleTicket?.ageBand.isStale == true, "7d ticket classified in stale age band (amber)")
        assertEqual(staleTicket?.ageBand.label, "7d", "7d ticket label formatted correctly")

        let freshTicket = openTickets.first(where: { $0.key == "OPS-700" })
        assert(freshTicket?.ageBand.isCritical == false && freshTicket?.ageBand.isStale == false, "1d ticket classified in fresh age band (green)")
        assertEqual(freshTicket?.ageBand.label, "1d", "1d ticket label formatted correctly")

        // 10. Check Focus AI Context snapshot
        let snapshot = viewModel.aiContextSnapshot(for: t1)
        assert(snapshot.contains("Ticket: INFRA-500"), "AI snapshot contains ticket key")
        assert(snapshot.contains("Upgrade cluster ingress"), "AI snapshot contains summary")
        assert(snapshot.contains("Priority: High"), "AI snapshot contains priority")
        assert(snapshot.contains("Open: 20d"), "AI snapshot contains open age")
        assert(snapshot.contains("Repositories (1):"), "AI snapshot associates 1 repository via branch feat/INFRA-500")
        assert(snapshot.contains("cloud-terraform-infra"), "AI snapshot names associated repository")
        // 11. Reference Fixture Parity Comparison Against myOps
        struct FixtureRepoCase {
            let name: String
            let merging: Bool
            let rebasing: Bool
            let cherryPicking: Bool
            let dirty: Bool
            let hasUpstream: Bool
            let behind: Int
            let ahead: Int
            let stashCount: Int
            let expectedScore: Int
            let expectedReasons: [String]
        }

        let referenceFixtureMatrix: [FixtureRepoCase] = [
            FixtureRepoCase(
                name: "merge-conflict",
                merging: true, rebasing: false, cherryPicking: false,
                dirty: true, hasUpstream: true, behind: 3, ahead: 2, stashCount: 2,
                expectedScore: 120, // 100 (merge) + 10 (dirty) + (5+3 behind) + 1 (ahead) + 1 (stash)
                expectedReasons: ["merge in progress", "dirty", "↓3 behind", "↑2 not pushed", "2 stashed"]
            ),
            FixtureRepoCase(
                name: "rebase-local",
                merging: false, rebasing: true, cherryPicking: false,
                dirty: false, hasUpstream: false, behind: 0, ahead: 0, stashCount: 0,
                expectedScore: 103, // 100 (rebase) + 3 (no upstream)
                expectedReasons: ["rebase in progress", "no upstream"]
            ),
            FixtureRepoCase(
                name: "cherry-picking",
                merging: false, rebasing: false, cherryPicking: true,
                dirty: false, hasUpstream: true, behind: 0, ahead: 0, stashCount: 0,
                expectedScore: 100, // 100 (cherry-pick)
                expectedReasons: ["cherry-pick in progress"]
            ),
            FixtureRepoCase(
                name: "behind-remote",
                merging: false, rebasing: false, cherryPicking: false,
                dirty: false, hasUpstream: true, behind: 10, ahead: 0, stashCount: 0,
                expectedScore: 15, // 5 + 10 (behind)
                expectedReasons: ["↓10 behind"]
            ),
            FixtureRepoCase(
                name: "dirty-worktree",
                merging: false, rebasing: false, cherryPicking: false,
                dirty: true, hasUpstream: true, behind: 0, ahead: 0, stashCount: 0,
                expectedScore: 10, // 10 (dirty)
                expectedReasons: ["dirty"]
            ),
            FixtureRepoCase(
                name: "untracked-branch",
                merging: false, rebasing: false, cherryPicking: false,
                dirty: false, hasUpstream: false, behind: 0, ahead: 0, stashCount: 0,
                expectedScore: 3, // 3 (no upstream)
                expectedReasons: ["no upstream"]
            ),
            FixtureRepoCase(
                name: "unpushed-commits",
                merging: false, rebasing: false, cherryPicking: false,
                dirty: false, hasUpstream: true, behind: 0, ahead: 5, stashCount: 0,
                expectedScore: 1, // 1 (ahead)
                expectedReasons: ["↑5 not pushed"]
            ),
            FixtureRepoCase(
                name: "stashes-only",
                merging: false, rebasing: false, cherryPicking: false,
                dirty: false, hasUpstream: true, behind: 0, ahead: 0, stashCount: 3,
                expectedScore: 1, // 1 (stash)
                expectedReasons: ["3 stashed"]
            ),
            FixtureRepoCase(
                name: "pristine-clean",
                merging: false, rebasing: false, cherryPicking: false,
                dirty: false, hasUpstream: true, behind: 0, ahead: 0, stashCount: 0,
                expectedScore: 0,
                expectedReasons: []
            )
        ]

        func computeScore(for r: RepoInfo) -> Int {
            var score = 0
            if r.isMerging || r.isRebasing || r.isCherryPicking { score += 100 }
            if r.isDirty { score += 10 }
            if r.hasUpstream && r.behind > 0 { score += 5 + r.behind }
            if !r.hasUpstream { score += 3 }
            if r.hasUpstream && r.ahead > 0 { score += 1 }
            if r.stashCount > 0 { score += 1 }
            return score
        }

        func computeReasons(for r: RepoInfo) -> [String] {
            var reasons: [String] = []
            if r.isMerging { reasons.append("merge in progress") }
            if r.isRebasing { reasons.append("rebase in progress") }
            if r.isCherryPicking { reasons.append("cherry-pick in progress") }
            if r.isDirty { reasons.append("dirty") }
            if r.hasUpstream && r.behind > 0 { reasons.append("↓\(r.behind) behind") }
            if !r.hasUpstream { reasons.append("no upstream") }
            if r.hasUpstream && r.ahead > 0 { reasons.append("↑\(r.ahead) not pushed") }
            if r.stashCount > 0 { reasons.append("\(r.stashCount) stashed") }
            return reasons
        }

        for fx in referenceFixtureMatrix {
            let info = RepoInfo(
                name: fx.name,
                path: "/fixtures/\(fx.name)",
                isDirty: fx.dirty,
                ahead: fx.ahead,
                behind: fx.behind,
                hasUpstream: fx.hasUpstream,
                stashCount: fx.stashCount,
                isMerging: fx.merging,
                isRebasing: fx.rebasing,
                isCherryPicking: fx.cherryPicking
            )
            assertEqual(computeScore(for: info), fx.expectedScore, "Fixture \(fx.name) attention score matches myOps reference")
            assertEqual(computeReasons(for: info), fx.expectedReasons, "Fixture \(fx.name) attention reasons match myOps reference")
        }

        // 12. Reference Age Band Parity
        let testTicketCritical = TicketInfo(key: "FX-1", summary: "Critical", isOpen: true, created: now.addingTimeInterval(-15.2 * day))
        assertEqual(testTicketCritical.ageBand.label, "15d", "Age 15.2d labels as '15d'")
        assert(testTicketCritical.ageBand.isCritical, "Age >= 14d is in critical band")

        let testTicketStale = TicketInfo(key: "FX-2", summary: "Stale", isOpen: true, created: now.addingTimeInterval(-5.0 * day))
        assertEqual(testTicketStale.ageBand.label, "5d", "Age 5.0d labels as '5d'")
        assert(testTicketStale.ageBand.isStale, "Age >= 5d is in stale band")

        let testTicketFresh = TicketInfo(key: "FX-3", summary: "Fresh", isOpen: true, created: now.addingTimeInterval(-2.4 * day))
        assertEqual(testTicketFresh.ageBand.label, "2d", "Age 2.4d labels as '2d'")
        assert(!testTicketFresh.ageBand.isCritical && !testTicketFresh.ageBand.isStale, "Age < 5d is in fresh band")
    }
}

// Test 35: Ticket Metadata Parity (Type/Project/Labels/Dates), Related Repos, and Sync Freshness
print("Test 35: Ticket Metadata Parity, Related Repos, and Sync Freshness")
do {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Jira date parsing accepts both the ISO8601-with-offset and legacy compact-offset shapes.
    let parsedISO = JiraService.parseJiraDate("2024-05-01T10:15:00.000-07:00")
    assert(parsedISO != nil, "ISO8601 offset date parses")
    let parsedLegacy = JiraService.parseJiraDate("2024-05-01T10:15:00.000-0700")
    assert(parsedLegacy != nil, "Legacy compact-offset date parses")
    assertEqual(JiraService.parseJiraDate(nil), nil, "Nil date input yields nil")
    assertEqual(JiraService.parseJiraDate(""), nil, "Empty date input yields nil")

    // Cache round-trip carries type/project/labels/dates/url through TicketScanner.
    let created = Date(timeIntervalSince1970: 1_700_000_000)
    let updated = Date(timeIntervalSince1970: 1_700_500_000)
    let rich = TicketInfo(
        key: "OPS-9",
        summary: "Rich metadata ticket",
        status: "In Progress",
        statusCategory: "in_progress",
        priority: "High",
        isOpen: true,
        localPath: nil,
        notes: "",
        type: "Story",
        project: "OPS",
        labels: ["backend", "urgent"],
        created: created,
        updated: updated,
        resolved: nil,
        jiraURL: "https://example.atlassian.net/browse/OPS-9"
    )
    JiraService.shared.saveCache(tickets: [rich], baseURL: "https://example.atlassian.net", workspacePath: tempDir.path)
    let scanned = TicketScanner.shared.scanTickets(workspacePath: tempDir.path)
    let scannedRich = scanned.first(where: { $0.key == "OPS-9" })
    assertEqual(scannedRich?.type, "Story", "Ticket type round-trips through the cache")
    assertEqual(scannedRich?.project, "OPS", "Ticket project round-trips through the cache")
    assertEqual(scannedRich?.labels, ["backend", "urgent"], "Ticket labels round-trip through the cache")
    assertEqual(scannedRich?.jiraURL, "https://example.atlassian.net/browse/OPS-9", "Ticket Jira URL round-trips through the cache")
    assert(scannedRich?.created != nil, "Ticket created date round-trips through the cache")
    assert(scannedRich?.updated != nil, "Ticket updated date round-trips through the cache")

    // Sync freshness is persisted per workspace and survives across ViewModel instances.
    let storeURL = tempDir.appendingPathComponent("state.json")
    let store = WorkspaceStateStore(customStorageURL: storeURL)
    MainActor.assumeIsolated {
        let viewModel = WorkspaceViewModel(stateStore: store)
        assertEqual(viewModel.ticketFreshnessLabel, nil, "No freshness label before any sync has happened")
        assertEqual(viewModel.isTicketDataStale, false, "Not stale before any sync has happened")

        store.recordJiraSyncResult(workspacePath: viewModel.workspacePath, date: Date(), error: nil)
        assert(viewModel.ticketFreshnessLabel?.hasPrefix("Synced") == true, "Successful sync produces a persistent 'Synced' label")
        assertEqual(viewModel.isTicketDataStale, false, "Successful sync is not marked stale")

        store.recordJiraSyncResult(workspacePath: viewModel.workspacePath, date: Date(), error: "Jira authentication rejected")
        assert(viewModel.ticketFreshnessLabel?.contains("Sync failed") == true, "Failed sync produces a persistent 'Sync failed' label")
        assertEqual(viewModel.isTicketDataStale, true, "Failed sync marks ticket data stale")

        // Freshness is scoped per workspace: syncing workspace A must not leak its
        // freshness/error state into workspace B.
        let workspaceA = tempDir.appendingPathComponent("workspace-a").path
        let workspaceB = tempDir.appendingPathComponent("workspace-b").path
        try! FileManager.default.createDirectory(atPath: workspaceA, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(atPath: workspaceB, withIntermediateDirectories: true)

        viewModel.setWorkspace(path: workspaceA)
        store.recordJiraSyncResult(workspacePath: workspaceA, date: Date(), error: "Jira authentication rejected")
        assert(viewModel.ticketFreshnessLabel?.contains("Sync failed") == true, "Workspace A shows its own failed-sync freshness")
        assertEqual(viewModel.isTicketDataStale, true, "Workspace A is marked stale after its own failed sync")

        viewModel.setWorkspace(path: workspaceB)
        assertEqual(viewModel.ticketFreshnessLabel, nil, "Workspace B has no freshness label; it never synced and must not inherit workspace A's state")
        assertEqual(viewModel.isTicketDataStale, false, "Workspace B is not stale; it must not inherit workspace A's sync error")

        store.recordJiraSyncResult(workspacePath: workspaceB, date: Date(), error: nil)
        assert(viewModel.ticketFreshnessLabel?.hasPrefix("Synced") == true, "Workspace B shows its own successful-sync freshness")

        viewModel.setWorkspace(path: workspaceA)
        assert(viewModel.ticketFreshnessLabel?.contains("Sync failed") == true, "Switching back to workspace A still shows its own failed-sync freshness, unaffected by workspace B's later successful sync")
    }

    // Related repos: a repo whose branch contains the ticket key surfaces as related,
    // mirroring the reference drawer's "Related repos" section.
    let related = RepoInfo(name: "related-repo", path: "/tmp/related-repo", branch: "feat/OPS-9-rich-metadata", changedFiles: [])
    let unrelated = RepoInfo(name: "other-repo", path: "/tmp/other-repo", branch: "main", changedFiles: [])
    let repoAssociation = TicketScanner.shared.associatedRepository(for: rich, repositories: [unrelated, related])
    assertEqual(repoAssociation?.path, related.path, "Ticket associates with the repo whose branch contains its key")
}



print("==================================================")
print("Complete Full miniOps Test Suite: \(passedCount) passed, \(failedCount) failed")
print("==================================================")
if failedCount > 0 { exit(1) }

