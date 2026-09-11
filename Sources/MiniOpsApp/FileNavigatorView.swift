import SwiftUI
import MiniOpsCore

public struct FileNavigatorView: View {
    public let repoPath: String
    public let rootNode: FileNode
    public let selectedFilePath: String?
    @Binding public var expandedFolderPaths: Set<String>
    public let onSelectFile: (String) -> Void
    public var onOpenInExternalEditor: ((String) -> Void)?
    public var onRevealInFinder: ((String) -> Void)?
    public var onCopyPath: ((String, Bool) -> Void)?

    public init(
        repoPath: String,
        rootNode: FileNode,
        selectedFilePath: String?,
        expandedFolderPaths: Binding<Set<String>>,
        onSelectFile: @escaping (String) -> Void,
        onOpenInExternalEditor: ((String) -> Void)? = nil,
        onRevealInFinder: ((String) -> Void)? = nil,
        onCopyPath: ((String, Bool) -> Void)? = nil
    ) {
        self.repoPath = repoPath
        self.rootNode = rootNode
        self.selectedFilePath = selectedFilePath
        self._expandedFolderPaths = expandedFolderPaths
        self.onSelectFile = onSelectFile
        self.onOpenInExternalEditor = onOpenInExternalEditor
        self.onRevealInFinder = onRevealInFinder
        self.onCopyPath = onCopyPath
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let children = rootNode.children {
                ForEach(children) { child in
                    FileNodeRow(
                        node: child,
                        depth: 0,
                        repoPath: repoPath,
                        selectedFilePath: selectedFilePath,
                        expandedFolderPaths: $expandedFolderPaths,
                        onSelectFile: onSelectFile,
                        onOpenInExternalEditor: onOpenInExternalEditor,
                        onRevealInFinder: onRevealInFinder,
                        onCopyPath: onCopyPath
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FileNodeRow: View {
    let node: FileNode
    let depth: Int
    let repoPath: String
    let selectedFilePath: String?
    @Binding var expandedFolderPaths: Set<String>
    let onSelectFile: (String) -> Void
    var onOpenInExternalEditor: ((String) -> Void)? = nil
    var onRevealInFinder: ((String) -> Void)? = nil
    var onCopyPath: ((String, Bool) -> Void)? = nil

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
            .contextMenu {
                Button {
                    if let onOpenInExternalEditor {
                        onOpenInExternalEditor(node.path)
                    } else {
                        ExternalEditor.open(path: node.path)
                    }
                } label: {
                    Label("Open in External Editor", systemImage: "arrow.up.forward.app")
                }

                Button {
                    if let onRevealInFinder {
                        onRevealInFinder(node.path)
                    } else {
                        NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: repoPath)
                    }
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }

                Divider()

                Button {
                    if let onCopyPath {
                        onCopyPath(node.path, false)
                    } else {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(node.path, forType: .string)
                    }
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }

                if node.path.hasPrefix(repoPath) {
                    Button {
                        let rel = String(node.path.dropFirst(repoPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        if let onCopyPath {
                            onCopyPath(node.path, true)
                        } else {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(rel, forType: .string)
                        }
                    } label: {
                        Label("Copy Relative Path", systemImage: "doc.on.clipboard")
                    }
                }
            }

            // Children if expanded
            if node.isDirectory && isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileNodeRow(
                        node: child,
                        depth: depth + 1,
                        repoPath: repoPath,
                        selectedFilePath: selectedFilePath,
                        expandedFolderPaths: $expandedFolderPaths,
                        onSelectFile: onSelectFile,
                        onOpenInExternalEditor: onOpenInExternalEditor,
                        onRevealInFinder: onRevealInFinder,
                        onCopyPath: onCopyPath
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
