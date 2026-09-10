import Foundation

public final class FileSystemService: @unchecked Sendable {
    public static let shared = FileSystemService()

    private let skipDirs: Set<String> = [
        ".git", ".build", "node_modules", "DerivedData", "Pods", ".DS_Store"
    ]

    public init() {}

    public func buildFileTree(for directoryPath: String, maxDepth: Int = 5) -> FileNode {
        let rootURL = URL(fileURLWithPath: (directoryPath as NSString).expandingTildeInPath).standardized
        return scanDirectory(url: rootURL, currentDepth: 0, maxDepth: maxDepth)
    }

    private func scanDirectory(url: URL, currentDepth: Int, maxDepth: Int) -> FileNode {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if !isDir || currentDepth >= maxDepth {
            return FileNode(name: url.lastPathComponent, path: url.path, isDirectory: isDir, children: nil)
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return FileNode(name: url.lastPathComponent, path: url.path, isDirectory: true, children: [])
        }

        var children: [FileNode] = []
        for childURL in contents.sorted(by: { a, b in
            let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if aIsDir != bIsDir {
                return aIsDir // directories first
            }
            return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }) {
            if skipDirs.contains(childURL.lastPathComponent) {
                continue
            }
            let childIsDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if childIsDir {
                children.append(scanDirectory(url: childURL, currentDepth: currentDepth + 1, maxDepth: maxDepth))
            } else {
                children.append(FileNode(name: childURL.lastPathComponent, path: childURL.path, isDirectory: false, children: nil))
            }
        }

        return FileNode(name: url.lastPathComponent, path: url.path, isDirectory: true, children: children)
    }

    public func validatePathWithin(repoPath: String, filePath: String) -> URL? {
        let repoURL = URL(fileURLWithPath: (repoPath as NSString).expandingTildeInPath).resolvingSymlinksInPath().standardized
        let fullURL: URL
        if filePath.hasPrefix("/") {
            fullURL = URL(fileURLWithPath: filePath).standardized
        } else {
            fullURL = repoURL.appendingPathComponent(filePath).standardized
        }

        // Resolve the existing ancestor too: Foundation leaves missing leaf paths unresolved.
        var ancestor = fullURL
        var missingComponents: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path) && ancestor.path != "/" {
            missingComponents.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var resolvedURL = ancestor.resolvingSymlinksInPath().standardized
        for component in missingComponents.reversed() {
            resolvedURL.appendPathComponent(component)
        }
        let prefix = repoURL.path.hasSuffix("/") ? repoURL.path : repoURL.path + "/"
        if resolvedURL.path.hasPrefix(prefix) {
            return resolvedURL
        }
        return nil
    }

    public func readFile(repoPath: String, filePath: String) throws -> String {
        guard let validURL = validatePathWithin(repoPath: repoPath, filePath: filePath) else {
            throw NSError(domain: "FileSystemService", code: 403, userInfo: [NSLocalizedDescriptionKey: "Access denied: Path escapes repository boundary: \(filePath)"])
        }
        return try String(contentsOf: validURL, encoding: .utf8)
    }

    public func writeFile(repoPath: String, filePath: String, content: String) throws {
        guard let validURL = validatePathWithin(repoPath: repoPath, filePath: filePath) else {
            throw NSError(domain: "FileSystemService", code: 403, userInfo: [NSLocalizedDescriptionKey: "Access denied: Path escapes repository boundary: \(filePath)"])
        }

        let parentDir = validURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try content.write(to: validURL, atomically: true, encoding: .utf8)
    }
}
