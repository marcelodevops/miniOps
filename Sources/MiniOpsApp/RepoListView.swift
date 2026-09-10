import SwiftUI
import MiniOpsCore

public struct RepoListView: View {
    public let repos: [RepoInfo]
    public let selectedRepoPath: String?
    public let fileTree: FileNode?
    public let selectedFilePath: String?
    @Binding public var expandedFolderPaths: Set<String>
    public let onSelectRepo: (RepoInfo) -> Void
    public let onSelectFile: (String) -> Void
    public var onHideRepo: ((RepoInfo) -> Void)?
    public var onAddToHerdr: ((RepoInfo) -> Void)?

    public init(
        repos: [RepoInfo],
        selectedRepoPath: String?,
        fileTree: FileNode?,
        selectedFilePath: String?,
        expandedFolderPaths: Binding<Set<String>>,
        onSelectRepo: @escaping (RepoInfo) -> Void,
        onSelectFile: @escaping (String) -> Void,
        onHideRepo: ((RepoInfo) -> Void)? = nil,
        onAddToHerdr: ((RepoInfo) -> Void)? = nil
    ) {
        self.repos = repos
        self.selectedRepoPath = selectedRepoPath
        self.fileTree = fileTree
        self.selectedFilePath = selectedFilePath
        self._expandedFolderPaths = expandedFolderPaths
        self.onSelectRepo = onSelectRepo
        self.onSelectFile = onSelectFile
        self.onHideRepo = onHideRepo
        self.onAddToHerdr = onAddToHerdr
    }

    public var body: some View {
        List {
            let grouped = Dictionary(grouping: repos, by: { $0.groupName ?? "" })
            let sortedKeys = grouped.keys.sorted { (a, b) -> Bool in
                if a.isEmpty { return true }
                if b.isEmpty { return false }
                return a.localizedStandardCompare(b) == .orderedAscending
            }

            ForEach(sortedKeys, id: \.self) { group in
                if !group.isEmpty {
                    Section(header: Text(group).font(.system(size: 11, weight: .bold)).foregroundColor(.secondary)) {
                        ForEach(grouped[group] ?? []) { repo in
                            repoTree(for: repo)
                        }
                    }
                } else {
                    ForEach(grouped[group] ?? []) { repo in
                        repoTree(for: repo)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func repoTree(for repo: RepoInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RepoRow(
                repo: repo,
                isSelected: repo.path == selectedRepoPath,
                onHideRepo: onHideRepo,
                onAddToHerdr: onAddToHerdr
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onSelectRepo(repo)
            }

            if repo.path == selectedRepoPath, let fileTree {
                FileNavigatorView(
                    repoPath: repo.path,
                    rootNode: fileTree,
                    selectedFilePath: selectedFilePath,
                    expandedFolderPaths: $expandedFolderPaths,
                    onSelectFile: onSelectFile
                )
                .padding(.leading, 12)
                .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RepoRow: View {
    let repo: RepoInfo
    let isSelected: Bool
    var onHideRepo: ((RepoInfo) -> Void)? = nil
    var onAddToHerdr: ((RepoInfo) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundColor(isSelected ? .white : .accentColor)
                .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(repo.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)

                    if repo.isDirty {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                            .help("Modified files present")
                    }
                }

                HStack(spacing: 6) {
                    // Branch badge
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                        Text(repo.branch)
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15))
                    )
                    .foregroundColor(isSelected ? .white : .secondary)

                    // Ahead/Behind indicators
                    if repo.ahead > 0 || repo.behind > 0 {
                        HStack(spacing: 2) {
                            if repo.ahead > 0 {
                                Text("↑\(repo.ahead)")
                                    .foregroundColor(.green)
                            }
                            if repo.behind > 0 {
                                Text("↓\(repo.behind)")
                                    .foregroundColor(.blue)
                            }
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contextMenu {
            Button {
                onAddToHerdr?(repo)
            } label: {
                Label("Create Herdr Workspace", systemImage: "rectangle.3.group")
            }

            Button {
                onHideRepo?(repo)
            } label: {
                Label("Hide Repository", systemImage: "eye.slash")
            }

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(repo.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repo.path)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
        }
    }
}
