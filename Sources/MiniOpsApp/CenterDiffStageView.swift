import SwiftUI
import AppKit
import MiniOpsCore

public struct CenterDiffStageView: View {
    @ObservedObject public var viewModel: WorkspaceViewModel
    @State private var commitMessage: String = ""
    @State private var isCommitting: Bool = false
    @State private var operationMessage: String?
    @State private var isErrorMessage: Bool = false

    // Asynchronous Diff Loading State
    @State private var diffContent: String = ""
    @State private var isLoadingDiff: Bool = false
    @State private var loadedDiffFile: String? = nil
    @State private var loadedRepoPath: String? = nil
    @State private var diffRequestToken: UUID = UUID()

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Stage Header
            diffStageHeader

            Divider()

            // Main Diff Content Area
            if let repo = viewModel.selectedRepo {
                if repo.changedFiles.isEmpty {
                    cleanWorkingTreePlaceholder
                } else {
                    diffContentView(for: repo)
                }
            } else {
                noRepoPlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            ensureActiveDiffFile()
            triggerDiffLoadIfNecessary()
        }
        .onChange(of: viewModel.selectedRepo?.path) { _ in
            ensureActiveDiffFile()
            triggerDiffLoadIfNecessary()
        }
        .onChange(of: viewModel.activeDiffFile) { _ in
            triggerDiffLoadIfNecessary()
        }
    }

    // MARK: - Header
    private var diffStageHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundColor(.accentColor)
                .font(.system(size: 13, weight: .bold))

            if let repo = viewModel.selectedRepo {
                Text(repo.name)
                    .font(.system(size: 12, weight: .bold))

                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                    Text(repo.branch)
                        .font(.system(size: 11, design: .monospaced))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))

                if !repo.changedFiles.isEmpty {
                    // File selector picker
                    Picker("", selection: Binding(
                        get: { viewModel.activeDiffFile ?? repo.changedFiles.first?.path ?? "" },
                        set: { newFile in
                            viewModel.activeDiffFile = newFile
                        }
                    )) {
                        ForEach(repo.changedFiles) { change in
                            HStack {
                                Text(change.statusLetter)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(statusColor(change.statusLetter))
                                Text(change.path)
                            }
                            .tag(change.path)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: 280)
                }

                if isLoadingDiff {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 4)
                }

                Spacer()

                // Actions for active file
                if let activeFile = currentActiveFile(for: repo),
                   repo.changedFiles.contains(where: { $0.path == activeFile }) {
                    Toggle("Include in Commit", isOn: Binding(
                        get: { viewModel.selectedFilesForCommit.contains(activeFile) },
                        set: { selected in
                            if selected {
                                viewModel.selectedFilesForCommit.insert(activeFile)
                            } else {
                                viewModel.selectedFilesForCommit.remove(activeFile)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))

                    Button(action: {
                        if viewModel.selectFile(activeFile) {
                            viewModel.selectCenterTab(.editor)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil.line")
                            Text("Open in Editor")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .help("Switch to Editor tab to modify this file")
                }
            } else {
                Text("Diff Inspector")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Diff Content
    private func diffContentView(for repo: RepoInfo) -> some View {
        VStack(spacing: 0) {
            let activeFile = currentActiveFile(for: repo) ?? ""

            if isLoadingDiff && diffContent.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    ProgressView()
                    Text("Loading diff for \(activeFile)...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if diffContent.isEmpty || diffContent == "No differences" {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text(diffContent.isEmpty ? "No diff available for \(activeFile)" : "No differences compared to HEAD")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(diffContent.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(diffLineColor(line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(diffLineBackground(line))
                        }
                    }
                    .padding(12)
                }
            }

            Divider()

            // Quick Commit Footer
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("Message:")
                        .font(.system(size: 11, weight: .semibold))
                    TextField("Commit message for selected files...", text: $commitMessage)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }

                if let msg = operationMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(isErrorMessage ? .red : .green)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: executeSelectiveCommit) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                        Text("Commit Selected (\(viewModel.selectedFilesForCommit.count))")
                    }
                    .font(.system(size: 11))
                }
                .disabled(viewModel.selectedFilesForCommit.isEmpty || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCommitting)

                Button(action: executeReconcile) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Reconcile")
                    }
                    .font(.system(size: 11))
                }
                .disabled(isCommitting || viewModel.selectedFilesForCommit.isEmpty)
                .help("Stage, commit with 'reconciling latest changes', and push")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    // MARK: - Placeholders
    private var cleanWorkingTreePlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)
            Text("Working Tree Clean")
                .font(.title3.bold())
            Text("There are no uncommitted changes in this repository.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Switch to Editor") {
                viewModel.selectCenterTab(.editor)
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noRepoPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No Repository Selected")
                .font(.title3.bold())
            Text("Select a repository from the left dock to inspect diffs.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func currentActiveFile(for repo: RepoInfo) -> String? {
        if let active = viewModel.activeDiffFile, repo.changedFiles.contains(where: { $0.path == active }) {
            return active
        }
        return repo.changedFiles.first?.path
    }

    private func ensureActiveDiffFile() {
        if let repo = viewModel.selectedRepo, !repo.changedFiles.isEmpty {
            if viewModel.activeDiffFile == nil || !repo.changedFiles.contains(where: { $0.path == viewModel.activeDiffFile }) {
                viewModel.activeDiffFile = repo.changedFiles.first?.path
            }
        }
    }

    private func triggerDiffLoadIfNecessary() {
        guard let repo = viewModel.selectedRepo, let active = currentActiveFile(for: repo) else {
            diffContent = ""
            loadedDiffFile = nil
            loadedRepoPath = nil
            return
        }

        if loadedRepoPath == repo.path && loadedDiffFile == active {
            return
        }

        loadDiffAsynchronously(repoPath: repo.path, filePath: active)
    }

    private func loadDiffAsynchronously(repoPath: String, filePath: String) {
        let token = UUID()
        self.diffRequestToken = token
        self.isLoadingDiff = true

        DispatchQueue.global(qos: .userInitiated).async {
            let diff = GitService.shared.getDiff(repoPath: repoPath, filePath: filePath)
            DispatchQueue.main.async {
                guard self.diffRequestToken == token else { return } // Discard outdated response
                self.diffContent = diff
                self.loadedDiffFile = filePath
                self.loadedRepoPath = repoPath
                self.isLoadingDiff = false
            }
        }
    }

    private func executeSelectiveCommit() {
        guard let repo = viewModel.selectedRepo else { return }
        let targetRepoPath = repo.path
        isCommitting = true
        operationMessage = "Committing selected files..."
        isErrorMessage = false

        let selected = Array(viewModel.selectedFilesForCommit)
        let message = commitMessage

        viewModel.executeSelectiveCommit(
            repoPath: targetRepoPath,
            message: message,
            selectedPaths: selected
        ) { result in
            self.isCommitting = false
            // Only update messages if active repo is still targetRepoPath
            guard self.viewModel.selectedRepo?.path == targetRepoPath else { return }
            if result.success {
                self.operationMessage = "Commit successful!"
                self.isErrorMessage = false
                self.commitMessage = ""
                self.triggerDiffLoadIfNecessary()
            } else {
                self.operationMessage = result.error ?? "Commit failed"
                self.isErrorMessage = true
            }
        }
    }

    private func executeReconcile() {
        guard let repo = viewModel.selectedRepo else { return }
        let targetRepoPath = repo.path
        isCommitting = true
        operationMessage = "Reconciling changes (commit & push)..."
        isErrorMessage = false

        let selected = Array(viewModel.selectedFilesForCommit)
        let msg = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "reconciling latest changes" : commitMessage

        viewModel.executeReconcile(
            repoPath: targetRepoPath,
            message: msg,
            selectedPaths: selected
        ) { result in
            self.isCommitting = false
            guard self.viewModel.selectedRepo?.path == targetRepoPath else { return }
            if result.success {
                self.operationMessage = result.output
                self.isErrorMessage = false
                self.commitMessage = ""
                self.triggerDiffLoadIfNecessary()
            } else {
                self.operationMessage = result.error ?? "Reconcile failed"
                self.isErrorMessage = true
                self.triggerDiffLoadIfNecessary()
            }
        }
    }

    private func statusColor(_ letter: String) -> Color {
        if letter.contains("M") { return .orange }
        if letter.contains("A") { return .green }
        if letter.contains("D") { return .red }
        if letter.contains("?") { return .purple }
        return .secondary
    }

    private func diffLineColor(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return .green
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return .red
        } else if line.hasPrefix("@@") {
            return .accentColor
        } else if line.hasPrefix("diff --git") {
            return .primary
        }
        return .secondary
    }

    private func diffLineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return Color.green.opacity(0.12)
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return Color.red.opacity(0.12)
        } else if line.hasPrefix("@@") {
            return Color.accentColor.opacity(0.08)
        }
        return Color.clear
    }
}
