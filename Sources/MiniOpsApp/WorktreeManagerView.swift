import SwiftUI
import MiniOpsCore

public struct WorktreeManagerView: View {
    public let repoPath: String
    public let onWorktreeChanged: () -> Void

    @State private var worktrees: [GitWorktreeItem] = []
    @State private var isShowingAddSheet: Bool = false
    @State private var newWorktreePath: String = ""
    @State private var newWorktreeBranch: String = ""
    @State private var statusMessage: String?
    @State private var isErrorMessage: Bool = false
    @State private var isProcessing: Bool = false

    public init(repoPath: String, onWorktreeChanged: @escaping () -> Void) {
        self.repoPath = repoPath
        self.onWorktreeChanged = onWorktreeChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Git Worktrees (\(worktrees.count))")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Button(action: reloadWorktrees) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)

                Button(action: { isShowingAddSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            List(worktrees) { wt in
                HStack(spacing: 8) {
                    Image(systemName: wt.isMain ? "folder.badge.gearshape" : "arrow.triangle.branch")
                        .foregroundColor(wt.isMain ? .accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(URL(fileURLWithPath: wt.path).lastPathComponent)
                                .font(.system(size: 12, weight: .semibold))
                            if wt.isMain {
                                Text("main")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                    .foregroundColor(.accentColor)
                            }
                        }

                        HStack(spacing: 6) {
                            if !wt.branch.isEmpty {
                                Text(wt.branch)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Text(wt.head)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Text(wt.path)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                            .lineLimit(1)
                    }

                    Spacer()

                    if !wt.isMain {
                        Button(role: .destructive, action: { removeWorktree(wt.path) }) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .help("Remove worktree")
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)

            if let msg = statusMessage {
                Divider()
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(isErrorMessage ? .red : .green)
                    .padding(8)
            }
        }
        .onAppear {
            reloadWorktrees()
        }
        .sheet(isPresented: $isShowingAddSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add New Worktree")
                    .font(.headline)

                TextField("Destination Directory Path", text: $newWorktreePath)
                    .textFieldStyle(.roundedBorder)

                TextField("New Branch Name (optional)", text: $newWorktreeBranch)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") {
                        isShowingAddSheet = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Add Worktree") {
                        addWorktree()
                    }
                    .disabled(newWorktreePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }

    private func reloadWorktrees() {
        worktrees = GitService.shared.listWorktrees(repoPath: repoPath)
    }

    private func addWorktree() {
        isProcessing = true
        let path = newWorktreePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = newWorktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newWorktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines)

        DispatchQueue.global(qos: .userInitiated).async {
            let res = GitService.shared.addWorktree(repoPath: repoPath, worktreePath: path, branch: nil, newBranch: branch)
            DispatchQueue.main.async {
                isProcessing = false
                if res.success {
                    isShowingAddSheet = false
                    newWorktreePath = ""
                    newWorktreeBranch = ""
                    statusMessage = "Worktree added."
                    isErrorMessage = false
                    reloadWorktrees()
                    onWorktreeChanged()
                } else {
                    statusMessage = res.error ?? "Failed to add worktree."
                    isErrorMessage = true
                }
            }
        }
    }

    private func removeWorktree(_ path: String) {
        isProcessing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let res = GitService.shared.removeWorktree(repoPath: repoPath, worktreePath: path, force: true)
            DispatchQueue.main.async {
                isProcessing = false
                if res.success {
                    statusMessage = "Worktree removed."
                    isErrorMessage = false
                    reloadWorktrees()
                    onWorktreeChanged()
                } else {
                    statusMessage = res.error ?? "Failed to remove worktree."
                    isErrorMessage = true
                }
            }
        }
    }
}
