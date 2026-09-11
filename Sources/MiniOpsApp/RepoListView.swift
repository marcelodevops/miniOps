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
    public var onOpenTerminal: ((RepoInfo) -> Void)?
    public var onOpenInExternalEditor: ((RepoInfo) -> Void)?
    public var onOpenRemote: ((RepoInfo) -> Void)?

    public init(
        repos: [RepoInfo],
        selectedRepoPath: String?,
        fileTree: FileNode?,
        selectedFilePath: String?,
        expandedFolderPaths: Binding<Set<String>>,
        onSelectRepo: @escaping (RepoInfo) -> Void,
        onSelectFile: @escaping (String) -> Void,
        onHideRepo: ((RepoInfo) -> Void)? = nil,
        onAddToHerdr: ((RepoInfo) -> Void)? = nil,
        onOpenTerminal: ((RepoInfo) -> Void)? = nil,
        onOpenInExternalEditor: ((RepoInfo) -> Void)? = nil,
        onOpenRemote: ((RepoInfo) -> Void)? = nil
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
        self.onOpenTerminal = onOpenTerminal
        self.onOpenInExternalEditor = onOpenInExternalEditor
        self.onOpenRemote = onOpenRemote
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
                onAddToHerdr: onAddToHerdr,
                onOpenTerminal: onOpenTerminal,
                onOpenInExternalEditor: onOpenInExternalEditor,
                onOpenRemote: onOpenRemote
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
    var onOpenTerminal: ((RepoInfo) -> Void)? = nil
    var onOpenInExternalEditor: ((RepoInfo) -> Void)? = nil
    var onOpenRemote: ((RepoInfo) -> Void)? = nil

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
                if let onOpenTerminal {
                    onOpenTerminal(repo)
                }
            } label: {
                Label("Open in Terminal", systemImage: "terminal")
            }

            Button {
                if let onOpenInExternalEditor {
                    onOpenInExternalEditor(repo)
                } else {
                    ExternalEditor.open(path: repo.path)
                }
            } label: {
                Label("Open in External Editor", systemImage: "arrow.up.forward.app")
            }

            if let remoteURL = GitService.shared.getRemoteWebURL(repoPath: repo.path) {
                Button {
                    if let onOpenRemote {
                        onOpenRemote(repo)
                    } else {
                        NSWorkspace.shared.open(remoteURL)
                    }
                } label: {
                    Label("Open Remote in Browser", systemImage: "safari")
                }
            }

            Divider()

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
