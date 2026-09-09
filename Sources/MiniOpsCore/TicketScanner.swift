import Foundation

public final class TicketScanner: @unchecked Sendable {
    public static let shared = TicketScanner()

    public init() {}

    public func scanTickets(workspacePath: String, repoPath: String? = nil) -> [TicketInfo] {
        var tickets: [TicketInfo] = []
        var seenKeys: Set<String> = []

        // 1. Check jira-cache.json in workspace or repo
        let possibleCachePaths = [
            URL(fileURLWithPath: (workspacePath as NSString).expandingTildeInPath).appendingPathComponent("jira-cache.json"),
            repoPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).appendingPathComponent("jira-cache.json") }
        ].compactMap { $0 }

        for cacheURL in possibleCachePaths {
            if let data = try? Data(contentsOf: cacheURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["tickets"] as? [[String: Any]] {
                for item in items {
                    guard let key = item["key"] as? String, !seenKeys.contains(key) else { continue }
                    let summary = item["summary"] as? String ?? "No summary"
                    let status = item["status"] as? String ?? "To Do"
                    let cat = (item["statusCategory"] as? String ?? "todo").lowercased()
                    let priority = item["priority"] as? String ?? "Medium"
                    let isOpen = cat != "done" && status.lowercased() != "closed"
                    seenKeys.insert(key)
                    tickets.append(TicketInfo(
                        key: key,
                        summary: summary,
                        status: status,
                        statusCategory: cat,
                        priority: priority,
                        isOpen: isOpen,
                        localPath: cacheURL.path,
                        notes: ""
                    ))
                }
            }
        }

        // 2. Check tickets/ directory in workspace or repo
        var searchDirs: [URL] = [
            URL(fileURLWithPath: (workspacePath as NSString).expandingTildeInPath).appendingPathComponent("tickets")
        ]
        if let rp = repoPath {
            searchDirs.append(URL(fileURLWithPath: (rp as NSString).expandingTildeInPath).appendingPathComponent("tickets"))
            searchDirs.append(URL(fileURLWithPath: (rp as NSString).expandingTildeInPath).appendingPathComponent(".tickets"))
        }

        for dir in searchDirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                continue
            }
            for file in files where file.pathExtension.lowercased() == "md" {
                let stem = file.deletingPathExtension().lastPathComponent
                let key = stem.components(separatedBy: "-").prefix(2).joined(separator: "-").uppercased()
                guard !seenKeys.contains(key) else { continue }

                if let content = try? String(contentsOf: file, encoding: .utf8) {
                    var summary = stem
                    var status = "To Do"
                    var cat = "todo"
                    var priority = "Medium"

                    for line in content.components(separatedBy: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("# ") {
                            summary = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                        } else if trimmed.lowercased().hasPrefix("status:") {
                            status = String(trimmed.dropFirst("status:".count)).trimmingCharacters(in: .whitespaces)
                            if status.lowercased().contains("done") || status.lowercased().contains("closed") {
                                cat = "done"
                            } else if status.lowercased().contains("progress") {
                                cat = "in_progress"
                            }
                        } else if trimmed.lowercased().hasPrefix("priority:") {
                            priority = String(trimmed.dropFirst("priority:".count)).trimmingCharacters(in: .whitespaces)
                        }
                    }

                    seenKeys.insert(key)
                    tickets.append(TicketInfo(
                        key: key,
                        summary: summary,
                        status: status,
                        statusCategory: cat,
                        priority: priority,
                        isOpen: cat != "done",
                        localPath: file.path,
                        notes: ""
                    ))
                }
            }
        }

        return tickets
    }

    public func makeFeatureBranchName(ticket: TicketInfo) -> String {
        let cleanKey = ticket.key.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let slug = ticket.summary.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(5)
            .joined(separator: "-")

        if slug.isEmpty {
            return "feat/\(cleanKey)"
        }
        return "feat/\(cleanKey)-\(slug)"
    }
}
