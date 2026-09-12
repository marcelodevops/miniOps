import Foundation

public final class TicketScanner: @unchecked Sendable {
    public static let shared = TicketScanner()

    public init() {}

    public func scanTickets(workspacePath: String, repoPath: String? = nil) -> [TicketInfo] {
        scanTickets(workspacePath: workspacePath, repoPaths: repoPath.map { [$0] } ?? [])
    }

    public func scanTickets(workspacePath: String, repoPaths: [String]) -> [TicketInfo] {
        var tickets: [TicketInfo] = []
        var seenKeys: Set<String> = []

        // 1. Check jira-cache.json in workspace or repo
        let workspaceURL = URL(fileURLWithPath: (workspacePath as NSString).expandingTildeInPath)
        let possibleCachePaths = [workspaceURL.appendingPathComponent("jira-cache.json")]
            + repoPaths.map {
                URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
                    .appendingPathComponent("jira-cache.json")
            }

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
                    let createdStr = (item["created"] as? String) ?? (item["createdDate"] as? String)
                    let createdDate = createdStr.flatMap { Self.parseDateString($0) }
                    seenKeys.insert(key)
                    tickets.append(TicketInfo(
                        key: key,
                        summary: summary,
                        status: status,
                        statusCategory: cat,
                        priority: priority,
                        isOpen: isOpen,
                        localPath: cacheURL.path,
                        notes: "",
                        type: item["type"] as? String,
                        project: item["project"] as? String,
                        labels: item["labels"] as? [String] ?? [],
                        created: createdDate,
                        updated: (item["updated"] as? String).flatMap { Self.parseDateString($0) },
                        resolved: (item["resolved"] as? String).flatMap { Self.parseDateString($0) },
                        jiraURL: item["url"] as? String
                    ))
                }
            }
        }

        // 2. Check tickets/ directory in workspace or repo
        var searchDirs = [workspaceURL.appendingPathComponent("tickets")]
        for repoPath in repoPaths {
            let repoURL = URL(fileURLWithPath: (repoPath as NSString).expandingTildeInPath)
            searchDirs.append(repoURL.appendingPathComponent("tickets"))
            searchDirs.append(repoURL.appendingPathComponent(".tickets"))
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
                    var createdDate: Date?

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
                        } else if trimmed.lowercased().hasPrefix("created:") {
                            let rawDate = String(trimmed.dropFirst("created:".count)).trimmingCharacters(in: .whitespaces)
                            createdDate = Self.parseDateString(rawDate)
                        }
                    }

                    if createdDate == nil, let attr = try? FileManager.default.attributesOfItem(atPath: file.path) {
                        createdDate = (attr[.creationDate] as? Date) ?? (attr[.modificationDate] as? Date)
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
                        notes: "",
                        created: createdDate
                    ))
                }
            }
        }

        return tickets
    }

    public static func parseDateString(_ s: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFormatter.date(from: s) { return d }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let d = isoFormatter.date(from: s) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            df.dateFormat = format
            if let d = df.date(from: s) { return d }
        }
        return nil
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

    /// Filters tickets for the navigator: optionally hides closed tickets and matches
    /// the query against the ticket key or summary.
    public func filter(tickets: [TicketInfo], searchText: String = "", openOnly: Bool = true) -> [TicketInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return tickets.filter { ticket in
            if openOnly && !ticket.isOpen { return false }
            if query.isEmpty { return true }
            return ticket.key.localizedCaseInsensitiveContains(query)
                || ticket.summary.localizedCaseInsensitiveContains(query)
        }
    }

    /// Converts a ticket's absolute local file path into a path relative to `repoPath`.
    /// Returns nil when the ticket file lives outside the repository, so a ticket stored
    /// in the workspace root can never be opened as if it belonged to the selected repo.
    public func repoRelativePath(forTicketPath ticketPath: String, repoPath: String) -> String? {
        let repoRoot = URL(fileURLWithPath: (repoPath as NSString).expandingTildeInPath).standardized.path
        let filePath = URL(fileURLWithPath: (ticketPath as NSString).expandingTildeInPath).standardized.path
        let prefix = repoRoot.hasSuffix("/") ? repoRoot : repoRoot + "/"

        guard filePath.hasPrefix(prefix) else { return nil }
        let relative = String(filePath.dropFirst(prefix.count))
        return relative.isEmpty ? nil : relative
    }

    /// Resolves a ticket to repository context without guessing from the currently
    /// selected repository. A local ticket file is authoritative; otherwise a
    /// branch containing the ticket key provides a useful Jira-to-repo association.
    public func associatedRepository(for ticket: TicketInfo, repositories: [RepoInfo]) -> RepoInfo? {
        if let localPath = ticket.localPath, localPath.lowercased().hasSuffix(".md") {
            let matching = repositories.filter {
                repoRelativePath(forTicketPath: localPath, repoPath: $0.path) != nil
            }
            if let deepest = matching.max(by: { $0.path.count < $1.path.count }) {
                return deepest
            }
        }

        if let branchMatch = repositories.first(where: { containsTicketKey(ticket.key, in: $0.branch) }) {
            return branchMatch
        }
        return repositories.first {
            let directoryName = URL(fileURLWithPath: $0.path).lastPathComponent
            return containsTicketKey(ticket.key, in: $0.name)
                || containsTicketKey(ticket.key, in: directoryName)
        }
    }

    private func containsTicketKey(_ key: String, in text: String) -> Bool {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = "(?i)(?<![A-Z0-9])\(escapedKey)(?![0-9])"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.firstMatch(in: text, range: range) != nil
    }
}
