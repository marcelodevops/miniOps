import SwiftUI
import AppKit
import MiniOpsCore

public struct GitChangesView: View {
    public let repoPath: String
    public let changes: [GitFileChange]
    @Binding public var selectedFilesForCommit: Set<String>
    @State private var currentlyViewingDiffFile: String?
    @State private var diffContent: String = ""
    @State private var commitMessage: String = ""
    @State private var isCommitting: Bool = false
    @State private var operationMessage: String?
    @State private var isErrorMessage: Bool = false
    @State private var listRatio: CGFloat = 0.3
    @State private var isDraggingDivider: Bool = false

    private static let dividerWidth: CGFloat = 1
    private static let splitSpace = "gitChangesSplit"

    public let onGitOperationDone: () -> Void

    public init(
        repoPath: String,
        changes: [GitFileChange],
        selectedFilesForCommit: Binding<Set<String>>,
        onGitOperationDone: @escaping () -> Void
    ) {
        self.repoPath = repoPath
        self.changes = changes
        self._selectedFilesForCommit = selectedFilesForCommit
        self.onGitOperationDone = onGitOperationDone
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
                HStack {
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

                                // View Diff Button
                                Button(action: {
                                    loadDiff(for: change.path)
                                }) {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.borderless)
                                .help("Inspect diff")
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
        let diff = GitService.shared.getDiff(repoPath: repoPath, filePath: path)
        diffContent = diff
    }

    private func executeSelectiveCommit() {
        isCommitting = true
        operationMessage = "Committing selected files..."
        isErrorMessage = false

        DispatchQueue.global(qos: .userInitiated).async {
            let result = GitService.shared.selectiveCommit(
                repoPath: repoPath,
                message: commitMessage,
                selectedPaths: Array(selectedFilesForCommit)
            )

            DispatchQueue.main.async {
                isCommitting = false
                if result.success {
                    operationMessage = "Commit successful!"
                    isErrorMessage = false
                    commitMessage = ""
                    selectedFilesForCommit.removeAll()
                    currentlyViewingDiffFile = nil
                    diffContent = ""
                    onGitOperationDone()
                } else {
                    operationMessage = result.error ?? "Commit failed"
                    isErrorMessage = true
                }
            }
        }
    }

    private func executeReconcile() {
        isCommitting = true
        operationMessage = "Reconciling changes (commit & push)..."
        isErrorMessage = false

        let selected = Array(selectedFilesForCommit)
        let msg = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "reconciling latest changes" : commitMessage

        DispatchQueue.global(qos: .userInitiated).async {
            let result = GitService.shared.reconcile(
                repoPath: repoPath,
                message: msg,
                selectedPaths: selected
            )

            DispatchQueue.main.async {
                isCommitting = false
                if result.success {
                    operationMessage = result.output
                    isErrorMessage = false
                    commitMessage = ""
                    selectedFilesForCommit.removeAll()
                    currentlyViewingDiffFile = nil
                    diffContent = ""
                    onGitOperationDone()
                } else {
                    if result.partialSuccess {
                        operationMessage = "Partial success: \(result.error ?? "")"
                        isErrorMessage = true
                    } else {
                        operationMessage = result.error ?? "Reconcile failed"
                        isErrorMessage = true
                    }
                    onGitOperationDone()
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
