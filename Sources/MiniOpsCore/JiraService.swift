import Foundation

public struct JiraVerifyResult: Sendable, Equatable {
    public let success: Bool
    public let displayName: String?
    public let email: String?
    public let error: String?

    public init(success: Bool, displayName: String? = nil, email: String? = nil, error: String? = nil) {
        self.success = success
        self.displayName = displayName
        self.email = email
        self.error = error
    }
}

public struct JiraSyncResult: Sendable, Equatable {
    public let success: Bool
    public let ticketCount: Int
    public let error: String?

    public init(success: Bool, ticketCount: Int = 0, error: String? = nil) {
        self.success = success
        self.ticketCount = ticketCount
        self.error = error
    }
}

/// Service for communicating with Atlassian Jira Cloud REST API.
public final class JiraService: @unchecked Sendable {
    public static let shared = JiraService()

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func normalizeBaseURL(_ rawURL: String) -> String {
        var base = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        if !base.isEmpty && !base.lowercased().hasPrefix("http://") && !base.lowercased().hasPrefix("https://") {
            base = "https://" + base
        }
        return base
    }

    public func createAuthHeader(email: String, token: String) -> String {
        let creds = "\(email.trimmingCharacters(in: .whitespacesAndNewlines)):\(token.trimmingCharacters(in: .whitespacesAndNewlines))"
        return "Basic " + Data(creds.utf8).base64EncodedString()
    }

    /// Verifies Jira credentials by querying `/rest/api/3/myself`.
    public func verifyCredentials(
        baseURL: String,
        email: String,
        token: String
    ) async -> JiraVerifyResult {
        let cleanBase = normalizeBaseURL(baseURL)
        guard !cleanBase.isEmpty else {
            return JiraVerifyResult(success: false, error: "Jira site URL is required.")
        }
        guard !email.isEmpty else {
            return JiraVerifyResult(success: false, error: "Account email is required.")
        }
        guard !token.isEmpty else {
            return JiraVerifyResult(success: false, error: "API token is required.")
        }

        guard let url = URL(string: "\(cleanBase)/rest/api/3/myself") else {
            return JiraVerifyResult(success: false, error: "Invalid Jira site URL: \(baseURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(createAuthHeader(email: email, token: token), forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return JiraVerifyResult(success: false, error: "Invalid response from server.")
            }

            if httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let displayName = json["displayName"] as? String
                    let emailAddress = json["emailAddress"] as? String
                    return JiraVerifyResult(success: true, displayName: displayName, email: emailAddress)
                }
                return JiraVerifyResult(success: true)
            } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return JiraVerifyResult(
                    success: false,
                    error: "Authentication failed (HTTP \(httpResponse.statusCode)). Check your email and Atlassian API token."
                )
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return JiraVerifyResult(
                    success: false,
                    error: "Jira returned HTTP \(httpResponse.statusCode): \(body.prefix(120))"
                )
            }
        } catch {
            return JiraVerifyResult(success: false, error: error.localizedDescription)
        }
    }

    /// Fetches assigned Jira tickets via the Atlassian search API.
    public func fetchTickets(
        baseURL: String,
        email: String,
        token: String,
        jql: String = "assignee = currentUser() ORDER BY updated DESC"
    ) async throws -> [TicketInfo] {
        let cleanBase = normalizeBaseURL(baseURL)
        guard !cleanBase.isEmpty else {
            throw NSError(domain: "JiraService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Jira site URL is missing."])
        }
        guard !email.isEmpty else {
            throw NSError(domain: "JiraService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Jira account email is missing."])
        }
        guard !token.isEmpty else {
            throw NSError(domain: "JiraService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Jira API token is missing."])
        }

        let searchEndpoint = "\(cleanBase)/rest/api/3/search/jql"
        guard let url = URL(string: searchEndpoint) else {
            throw NSError(domain: "JiraService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Jira endpoint URL: \(searchEndpoint)"])
        }

        let authHeader = createAuthHeader(email: email, token: token)
        let fields = ["summary", "status", "issuetype", "priority", "created", "updated", "resolutiondate", "project", "labels"]

        var allTickets: [TicketInfo] = []
        var nextPageToken: String? = nil
        var guardCount = 0

        while true {
            guardCount += 1
            if guardCount > 20 { break }

            var payload: [String: Any] = [
                "jql": jql,
                "maxResults": 100,
                "fields": fields
            ]
            if let page = nextPageToken {
                payload["nextPageToken"] = page
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            request.timeoutInterval = 30

            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "JiraService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid network response."])
            }

            if httpResponse.statusCode != 200 {
                let errString = String(data: data, encoding: .utf8) ?? ""
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw NSError(
                        domain: "JiraService",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Jira authentication rejected (HTTP \(httpResponse.statusCode)). Check your token and email."]
                    )
                }
                throw NSError(
                    domain: "JiraService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Jira HTTP \(httpResponse.statusCode): \(errString.prefix(120))"]
                )
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let issues = json["issues"] as? [[String: Any]] else {
                throw NSError(domain: "JiraService", code: 502, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response from Jira search API."])
            }

            for issue in issues {
                guard let key = issue["key"] as? String else { continue }
                let f = issue["fields"] as? [String: Any] ?? [:]
                let summary = f["summary"] as? String ?? "No summary"
                let statusDict = f["status"] as? [String: Any] ?? [:]
                let statusName = statusDict["name"] as? String ?? "To Do"
                let statusCategoryDict = statusDict["statusCategory"] as? [String: Any] ?? [:]
                let rawCat = ((statusCategoryDict["name"] as? String) ?? "todo").lowercased()

                let cat: String
                if rawCat.contains("done") || rawCat.contains("complete") {
                    cat = "done"
                } else if rawCat.contains("progress") {
                    cat = "in_progress"
                } else {
                    cat = "todo"
                }

                let priorityDict = f["priority"] as? [String: Any] ?? [:]
                let priorityName = priorityDict["name"] as? String ?? "None"
                let isOpen = cat != "done" && statusName.lowercased() != "closed"
                let createdStr = f["created"] as? String
                let createdDate = createdStr.flatMap { TicketScanner.parseDateString($0) }

                let ticket = TicketInfo(
                    key: key,
                    summary: summary,
                    status: statusName,
                    statusCategory: cat,
                    priority: priorityName,
                    isOpen: isOpen,
                    localPath: nil,
                    notes: "",
                    created: createdDate
                )
                allTickets.append(ticket)
            }

            let isLast = json["isLast"] as? Bool ?? true
            let tokenPage = json["nextPageToken"] as? String
            if isLast || tokenPage == nil || tokenPage == nextPageToken {
                break
            }
            nextPageToken = tokenPage
        }

        return allTickets
    }

    /// Syncs tickets from Jira, caches them to disk, and returns a result summary.
    public func syncTickets(workspacePath: String) async -> JiraSyncResult {
        let settings = WorkspaceStateStore.shared.getIntegrationSettings()
        let cleanBase = normalizeBaseURL(settings.jiraBaseURL)
        let email = settings.jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanBase.isEmpty, !email.isEmpty else {
            return JiraSyncResult(success: false, error: "Jira site URL and account email must be configured in Settings.")
        }
        guard let token = CredentialStore.shared.readSecret(for: .jira), !token.isEmpty else {
            return JiraSyncResult(success: false, error: "No Jira API token found in the macOS Keychain.")
        }

        do {
            let tickets = try await fetchTickets(baseURL: cleanBase, email: email, token: token)
            saveCache(tickets: tickets, baseURL: cleanBase, workspacePath: workspacePath)
            return JiraSyncResult(success: true, ticketCount: tickets.count)
        } catch {
            return JiraSyncResult(success: false, error: error.localizedDescription)
        }
    }

    /// Saves ticket data in JSON format matching jira-cache.json for consumption by TicketScanner.
    public func saveCache(tickets: [TicketInfo], baseURL: String, workspacePath: String) {
        let ticketDicts: [[String: Any]] = tickets.map { ticket in
            [
                "key": ticket.key,
                "summary": ticket.summary,
                "status": ticket.status,
                "statusCategory": ticket.statusCategory,
                "priority": ticket.priority,
                "type": "Task",
                "isOpen": ticket.isOpen,
                "url": "\(baseURL)/browse/\(ticket.key)"
            ]
        }

        let cacheJSON: [String: Any] = [
            "filter": "assignee = currentUser() ORDER BY updated DESC",
            "fetched_count": tickets.count,
            "tickets": ticketDicts
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: cacheJSON, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }

        // Save to workspace root ((workspacePath)/jira-cache.json)
        let wsURL = URL(fileURLWithPath: (workspacePath as NSString).expandingTildeInPath)
        let wsCacheURL = wsURL.appendingPathComponent("jira-cache.json")
        try? data.write(to: wsCacheURL, options: .atomic)
    }
}
