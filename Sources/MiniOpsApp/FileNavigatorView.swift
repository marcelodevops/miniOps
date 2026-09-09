import SwiftUI
import MiniOpsCore

public struct FileNavigatorView: View {
    public let repoPath: String
    public let rootNode: FileNode
    public let selectedFilePath: String?
    @Binding public var expandedFolderPaths: Set<String>
    public let onSelectFile: (String) -> Void

    public init(
        repoPath: String,
        rootNode: FileNode,
        selectedFilePath: String?,
        expandedFolderPaths: Binding<Set<String>>,
        onSelectFile: @escaping (String) -> Void
    ) {
        self.repoPath = repoPath
        self.rootNode = rootNode
        self.selectedFilePath = selectedFilePath
        self._expandedFolderPaths = expandedFolderPaths
        self.onSelectFile = onSelectFile
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if let children = rootNode.children {
                    ForEach(children) { child in
                        FileNodeRow(
                            node: child,
                            depth: 0,
                            selectedFilePath: selectedFilePath,
                            expandedFolderPaths: $expandedFolderPaths,
                            onSelectFile: onSelectFile
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct FileNodeRow: View {
    let node: FileNode
    let depth: Int
    let selectedFilePath: String?
    @Binding var expandedFolderPaths: Set<String>
    let onSelectFile: (String) -> Void

    var isExpanded: Bool {
        expandedFolderPaths.contains(node.path)
    }

    var isSelected: Bool {
        selectedFilePath == node.path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                // Indentation
                if depth > 0 {
                    Spacer()
                        .frame(width: CGFloat(depth * 14))
                }

                // Disclosure indicator
                if node.isDirectory {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                } else {
                    Spacer().frame(width: 12)
                }

                // Icon
                Image(systemName: iconForNode(node))
                    .foregroundColor(colorForNode(node))
                    .font(.system(size: 11))
                    .frame(width: 14)

                // Name
                Text(node.name)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if node.isDirectory {
                    if isExpanded {
                        expandedFolderPaths.remove(node.path)
                    } else {
                        expandedFolderPaths.insert(node.path)
                    }
                } else {
                    onSelectFile(node.path)
                }
            }

            // Children if expanded
            if node.isDirectory && isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileNodeRow(
                        node: child,
                        depth: depth + 1,
                        selectedFilePath: selectedFilePath,
                        expandedFolderPaths: $expandedFolderPaths,
                        onSelectFile: onSelectFile
                    )
                }
            }
        }
    }

    private func iconForNode(_ node: FileNode) -> String {
        if node.isDirectory {
            return isExpanded ? "folder.fill" : "folder"
        }
        let ext = URL(fileURLWithPath: node.path).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "json": return "curlybraces.square"
        case "md", "markdown", "txt": return "doc.plaintext"
        case "sh", "zsh", "bash": return "terminal"
        case "yml", "yaml", "toml": return "slider.horizontal.3"
        default: return "doc"
        }
    }

    private func colorForNode(_ node: FileNode) -> Color {
        if node.isDirectory {
            return .accentColor
        }
        let ext = URL(fileURLWithPath: node.path).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "py": return .yellow
        case "js", "ts", "jsx", "tsx": return .blue
        case "json": return .purple
        case "md": return .teal
        case "sh", "zsh": return .green
        default: return .secondary
        }
    }
}
