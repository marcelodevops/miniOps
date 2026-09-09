import Foundation

public final class NotesService: @unchecked Sendable {
    public static let shared = NotesService()

    private let storageURL: URL
    private let queue = DispatchQueue(label: "miniops.notes.service")
    private var cache: [String: String] = [:]

    public init(customStorageURL: URL? = nil) {
        if let customURL = customStorageURL {
            self.storageURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let miniOpsDir = appSupport.appendingPathComponent("miniOps", isDirectory: true)
            try? FileManager.default.createDirectory(at: miniOpsDir, withIntermediateDirectories: true)
            self.storageURL = miniOpsDir.appendingPathComponent("repo-notes.json")
        }

        if let data = try? Data(contentsOf: storageURL),
           let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.cache = loaded
        }
    }

    public func getNote(for repoPath: String) -> String {
        let norm = URL(fileURLWithPath: (repoPath as NSString).expandingTildeInPath).standardized.path
        return queue.sync { cache[norm] ?? "" }
    }

    public func saveNote(for repoPath: String, note: String) {
        let norm = URL(fileURLWithPath: (repoPath as NSString).expandingTildeInPath).standardized.path
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        queue.sync {
            if trimmed.isEmpty {
                cache.removeValue(forKey: norm)
            } else {
                cache[norm] = String(trimmed.prefix(4000))
            }
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
