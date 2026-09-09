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
