import SwiftUI
import AppKit
import MiniOpsCore

public struct GitChangesView: View {
    public let repoPath: String
    public let changes: [GitFileChange]
    public let statusRevision: Int
    @Binding public var selectedFilesForCommit: Set<String>
    @State private var currentlyViewingDiffFile: String?
    @State private var diffContent: String = ""
    @State private var commitMessage: String = ""
    @State private var isCommitting: Bool = false
    @State private var operationMessage: String?
    @State private var isErrorMessage: Bool = false
    @State private var listRatio: CGFloat = 0.3
    @State private var isDraggingDivider: Bool = false
    @State private var diffRequestToken: UUID = UUID()

    private static let dividerWidth: CGFloat = 1
    private static let splitSpace = "gitChangesSplit"

    public let onGitOperationDone: () -> Void
    public var onOpenStashes: (() -> Void)?
    public var onOpenWorktrees: (() -> Void)?
    public var onOpenBatchGit: (() -> Void)?
    public var onInspectDiffInCenter: ((String) -> Void)?
    public var onExecuteCommit: ((_ repoPath: String, _ message: String, _ selectedPaths: [String], _ completion: @escaping (GitOperationResult) -> Void) -> Void)?
    public var onExecuteReconcile: ((_ repoPath: String, _ message: String, _ selectedPaths: [String], _ completion: @escaping (GitOperationResult) -> Void) -> Void)?
    public var currentRepoPath: (() -> String?)?
    public var onDiffLoaded: ((_ filePath: String, _ content: String) -> Void)?

    public init(
        repoPath: String,
        changes: [GitFileChange],
        statusRevision: Int = 0,
        selectedFilesForCommit: Binding<Set<String>>,
        onGitOperationDone: @escaping () -> Void,
        onOpenStashes: (() -> Void)? = nil,
        onOpenWorktrees: (() -> Void)? = nil,
        onOpenBatchGit: (() -> Void)? = nil,
        onInspectDiffInCenter: ((String) -> Void)? = nil,
        onExecuteCommit: ((_ repoPath: String, _ message: String, _ selectedPaths: [String], _ completion: @escaping (GitOperationResult) -> Void) -> Void)? = nil,
        onExecuteReconcile: ((_ repoPath: String, _ message: String, _ selectedPaths: [String], _ completion: @escaping (GitOperationResult) -> Void) -> Void)? = nil,
        currentRepoPath: (() -> String?)? = nil,
        onDiffLoaded: ((_ filePath: String, _ content: String) -> Void)? = nil
    ) {
        self.repoPath = repoPath
        self.changes = changes
        self.statusRevision = statusRevision
        self._selectedFilesForCommit = selectedFilesForCommit
        self.onGitOperationDone = onGitOperationDone
        self.onOpenStashes = onOpenStashes
        self.onOpenWorktrees = onOpenWorktrees
        self.onOpenBatchGit = onOpenBatchGit
        self.onInspectDiffInCenter = onInspectDiffInCenter
        self.onExecuteCommit = onExecuteCommit
        self.onExecuteReconcile = onExecuteReconcile
        self.currentRepoPath = currentRepoPath
        self.onDiffLoaded = onDiffLoaded
    }

    public var body: some View {
        // A proportional split instead of HSplitView: NSSplitView keeps absolute
        // divider positions, so toggling the NavigationSplitView sidebar left the
        // file list stranded under it. Recomputing from the live container width
        // keeps both panes inside the detail pane at every width.
        GeometryReader { geometry in
            let layout = SplitPaneLayout.resolve(
                totalWidth: geometry.size.width,
                ratio: listRatio,
                dividerWidth: Self.dividerWidth
            )

            HStack(spacing: 0) {
                fileListPane
                    .frame(width: layout.leadingWidth)
                    .clipped()

                divider(totalWidth: geometry.size.width)

                diffPane
                    .frame(width: layout.trailingWidth)
                    .clipped()
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .coordinateSpace(name: Self.splitSpace)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            if let first = changes.first {
                loadDiff(for: first.path)
            }
        }
        .onChange(of: repoPath) { _, _ in
            diffRequestToken = UUID()
            currentlyViewingDiffFile = nil
            diffContent = ""
            operationMessage = nil
            isErrorMessage = false
        }
        .onChange(of: statusRevision) { _, _ in
            if let file = currentlyViewingDiffFile {
                loadDiff(for: file)
            } else if let first = changes.first {
                loadDiff(for: first.path)
            }
        }
        .onChange(of: changes) { _, newChanges in
            if let file = currentlyViewingDiffFile {
                if !newChanges.contains(where: { $0.path == file }) {
                    currentlyViewingDiffFile = nil
                    diffContent = ""
                    diffRequestToken = UUID()
                } else {
                    loadDiff(for: file)
                }
            }
        }
    }

    private func divider(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(isDraggingDivider ? Color.accentColor : Color(NSColor.separatorColor))
            .frame(width: Self.dividerWidth)
            .overlay(
                // Thin dividers are hard to grab, so widen only the hit area.
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 9)
                    .contentShape(Rectangle())
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.splitSpace))
                    .onChanged { value in
                        isDraggingDivider = true
                        listRatio = SplitPaneLayout.ratio(
                            forLeadingWidth: value.location.x,
                            totalWidth: totalWidth,
                            dividerWidth: Self.dividerWidth
                        )
                    }
                    .onEnded { _ in
                        isDraggingDivider = false
                    }
            )
    }

    private var fileListPane: some View {
        // Left list: Changed files with selection checkboxes
        VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 6) {
                    Text("Git Changes (\(changes.count))")
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    Button("All") {
                        selectedFilesForCommit = Set(changes.map { $0.path })
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))

                    Button("None") {
                        selectedFilesForCommit.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))

                    Menu {
                        if let onInspectDiffInCenter, let file = currentlyViewingDiffFile {
                            Button("Open Current Diff in Center Stage") {
                                onInspectDiffInCenter(file)
                            }
                            Divider()
                        }
                        if let onOpenStashes {
                            Button("Manage Stashes...") {
                                onOpenStashes()
                            }
                        }
                        if let onOpenWorktrees {
                            Button("Manage Worktrees...") {
                                onOpenWorktrees()
                            }
                        }
                        if let onOpenBatchGit {
                            Button("Batch Git Operations...") {
                                onOpenBatchGit()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 11))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Git context tools (Stashes, Worktrees, Batch Git)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // List of files
                if changes.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                        Text("Working tree clean")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(changes) { change in
                            HStack(spacing: 6) {
                                // Commit selection checkbox (SEPARATE from diff viewing)
                                Toggle("", isOn: Binding(
                                    get: { selectedFilesForCommit.contains(change.path) },
                                    set: { selected in
                                        if selected {
                                            selectedFilesForCommit.insert(change.path)
                                        } else {
                                            selectedFilesForCommit.remove(change.path)
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .help("Include in commit")

                                // Status badge
                                Text(change.statusLetter)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(statusColor(change.statusLetter))
                                    .frame(width: 20, alignment: .leading)

                                // File path (clicking selects for diff view)
                                Text(change.path)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundColor(currentlyViewingDiffFile == change.path ? .accentColor : .primary)

                                Spacer()

                                // Inspect in center stage button
                                if let onInspectDiffInCenter {
                                    Button(action: {
                                        currentlyViewingDiffFile = change.path
                                        onInspectDiffInCenter(change.path)
                                    }) {
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Inspect full diff in Center Stage")
                                }

                                // View Diff Button
                                Button(action: {
                                    loadDiff(for: change.path)
                                }) {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.borderless)
                                .help("Inspect diff in pane")
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                loadDiff(for: change.path)
                            }
                        }
                    }
                    .listStyle(.plain)
                }

                Divider()

                // Commit Box
                VStack(alignment: .leading, spacing: 6) {
                    Text("Commit Message:")
                        .font(.system(size: 11, weight: .semibold))

                    TextEditor(text: $commitMessage)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 55)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

                    if let msg = operationMessage {
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundColor(isErrorMessage ? .red : .green)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        Button(action: executeSelectiveCommit) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle")
                                Text("Commit Selected (\(selectedFilesForCommit.count))")
                            }
                        }
                        .disabled(selectedFilesForCommit.isEmpty || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCommitting)

                        Spacer()

                        Button(action: executeReconcile) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Reconcile")
                            }
                        }
                        .disabled(isCommitting || selectedFilesForCommit.isEmpty)
                        .help("Stage, commit with 'reconciling latest changes', and push")
                    }
                }
                .padding(10)
                .background(Color(NSColor.windowBackgroundColor))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var diffPane: some View {
        // Right Pane: One file's diff viewer at a time
        VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundColor(.accentColor)
                    if let file = currentlyViewingDiffFile {
                        Text("Diff: \(file)")
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        Text("Select a file to inspect its diff")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    if let onInspectDiffInCenter, let file = currentlyViewingDiffFile {
                        Button(action: {
                            onInspectDiffInCenter(file)
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                Text("Center")
                            }
                            .font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .help("Expand diff to Center Stage")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                if diffContent.isEmpty {
                    VStack {
                        Spacer()
                        Text("No diff selected")
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
                        .padding(8)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func loadDiff(for path: String) {
        currentlyViewingDiffFile = path
        let token = UUID()
        self.diffRequestToken = token
        let targetRepo = repoPath
        DispatchQueue.global(qos: .userInitiated).async {
            let diff = GitService.shared.getDiff(repoPath: targetRepo, filePath: path)
            DispatchQueue.main.async {
                guard self.diffRequestToken == token else { return }
                guard (self.currentRepoPath?() ?? self.repoPath) == targetRepo else { return }
                self.diffContent = diff
                self.onDiffLoaded?(path, diff)
            }
        }
    }

    private func executeSelectiveCommit() {
        let targetRepoPath = repoPath
        let message = commitMessage
        let selectedPaths = Array(selectedFilesForCommit)
        isCommitting = true
        operationMessage = "Committing selected files..."
        isErrorMessage = false

        let handleResult: (GitOperationResult) -> Void = { result in
            isCommitting = false
            let isCurrent = (currentRepoPath?() ?? self.repoPath) == targetRepoPath
            if result.success {
                if isCurrent {
                    operationMessage = "Commit successful!"
                    isErrorMessage = false
                    commitMessage = ""
                    currentlyViewingDiffFile = nil
                    diffContent = ""
                    onGitOperationDone()
                }
            } else {
                if isCurrent {
                    operationMessage = result.error ?? "Commit failed"
                    isErrorMessage = true
                }
            }
        }

        if let onExecuteCommit {
            onExecuteCommit(targetRepoPath, message, selectedPaths) { result in
                handleResult(result)
            }
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                let result = GitService.shared.selectiveCommit(
                    repoPath: targetRepoPath,
                    message: message,
                    selectedPaths: selectedPaths
                )
                DispatchQueue.main.async {
                    if result.success {
                        var state = WorkspaceStateStore.shared.getRepoState(repoPath: targetRepoPath)
                        state.selectedFilesForCommit = []
                        WorkspaceStateStore.shared.saveRepoState(repoPath: targetRepoPath, state: state)
                    }
                    handleResult(result)
                }
            }
        }
    }

    private func executeReconcile() {
        let targetRepoPath = repoPath
        let selectedPaths = Array(selectedFilesForCommit)
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "reconciling latest changes" : commitMessage
        isCommitting = true
        operationMessage = "Reconciling changes (commit & push)..."
        isErrorMessage = false

        let handleResult: (GitOperationResult) -> Void = { result in
            isCommitting = false
            let isCurrent = (currentRepoPath?() ?? self.repoPath) == targetRepoPath
            if result.success {
                if isCurrent {
                    operationMessage = result.output.isEmpty ? "Reconciled successfully!" : result.output
                    isErrorMessage = false
                    commitMessage = ""
                    currentlyViewingDiffFile = nil
                    diffContent = ""
                    onGitOperationDone()
                }
            } else if result.partialSuccess {
                if isCurrent {
                    operationMessage = "Partial success: \(result.error ?? "")"
                    isErrorMessage = true
                    commitMessage = ""
                    onGitOperationDone()
                }
            } else {
                if isCurrent {
                    operationMessage = result.error ?? "Reconcile failed"
                    isErrorMessage = true
                }
            }
        }

        if let onExecuteReconcile {
            onExecuteReconcile(targetRepoPath, message, selectedPaths) { result in
                handleResult(result)
            }
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                let result = GitService.shared.reconcile(
                    repoPath: targetRepoPath,
                    message: message,
                    selectedPaths: selectedPaths
                )
                DispatchQueue.main.async {
                    if result.success {
                        var state = WorkspaceStateStore.shared.getRepoState(repoPath: targetRepoPath)
                        state.selectedFilesForCommit = []
                        WorkspaceStateStore.shared.saveRepoState(repoPath: targetRepoPath, state: state)
                    }
                    handleResult(result)
                }
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
