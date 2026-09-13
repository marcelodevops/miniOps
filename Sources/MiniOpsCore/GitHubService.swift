import Foundation

public struct RemoteRepoItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String { nameWithOwner }
    public let nameWithOwner: String
    public let isPrivate: Bool
    public let description: String
    public let updatedAt: String?

    public init(nameWithOwner: String, isPrivate: Bool, description: String = "", updatedAt: String? = nil) {
        self.nameWithOwner = nameWithOwner
        self.isPrivate = isPrivate
        self.description = description
        self.updatedAt = updatedAt
    }

    public var name: String {
        nameWithOwner.components(separatedBy: "/").last ?? nameWithOwner
    }

    public var owner: String {
        nameWithOwner.components(separatedBy: "/").first ?? ""
    }
}

public struct CloneResult: Equatable, Sendable {
    public let success: Bool
    public let destinationPath: String?
    public let error: String?

    public init(success: Bool, destinationPath: String? = nil, error: String? = nil) {
        self.success = success
        self.destinationPath = destinationPath
        self.error = error
    }
}

public struct CreateRemoteRepoResult: Equatable, Sendable {
    public let success: Bool
    public let remoteUrl: String?
    public let destinationPath: String?
    public let error: String?

    public init(success: Bool, remoteUrl: String? = nil, destinationPath: String? = nil, error: String? = nil) {
        self.success = success
        self.remoteUrl = remoteUrl
        self.destinationPath = destinationPath
        self.error = error
    }
}

public final class GitHubService: @unchecked Sendable {
    public static let shared = GitHubService()

    private let repoNameRegex = try! NSRegularExpression(pattern: "^[A-Za-z0-9_.-]+$")

    public init() {}

    public func findGitHubCLI() -> String? {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
            "/bin/gh"
        ]
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public func checkAuthentication() -> (authenticated: Bool, username: String?) {
        guard let gh = findGitHubCLI() else {
            return (false, nil)
        }

        let (status, stdout, _) = runProcess(executable: gh, args: ["api", "user", "--jq", ".login"], in: NSHomeDirectory(), timeout: 10)
        if status == 0 {
            let user = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !user.isEmpty {
                return (true, user)
            }
        }
        return (false, nil)
    }

    public func verifyCredentials(username: String = "", token: String) async -> (success: Bool, authenticatedUser: String?, error: String?) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            return (false, nil, "GitHub Personal Access Token is required.")
        }
        guard let url = URL(string: "https://api.github.com/user") else {
            return (false, nil, "Invalid GitHub API URL.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.setValue("miniOps-App", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return (false, nil, "Invalid server response.")
            }
            if http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let login = json["login"] as? String {
                    let expected = username.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !expected.isEmpty && expected.caseInsensitiveCompare(login) != .orderedSame {
                        return (true, login, "Authenticated as '\(login)' (different from entered '\(expected)').")
                    }
                    return (true, login, nil)
                }
                return (true, nil, nil)
            } else if http.statusCode == 401 {
                return (false, nil, "Bad credentials: Token is invalid or expired (HTTP 401).")
            } else if http.statusCode == 403 {
                return (false, nil, "Forbidden: Rate limited or insufficient token scopes (HTTP 403).")
            } else {
                return (false, nil, "GitHub API returned status code \(http.statusCode).")
            }
        } catch {
            return (false, nil, "Network request failed: \(error.localizedDescription)")
        }
    }

    public func fetchUserRepositories(limit: Int = 100) -> [RemoteRepoItem] {
        guard let gh = findGitHubCLI() else { return [] }

        let args = ["repo", "list", "--limit", "\(limit)", "--json", "nameWithOwner,isPrivate,description,updatedAt"]
        let (status, stdout, _) = runProcess(executable: gh, args: args, in: NSHomeDirectory(), timeout: 20)

        guard status == 0, let data = stdout.data(using: .utf8) else {
            return []
        }

        do {
            let items = try JSONDecoder().decode([RemoteRepoItem].self, from: data)
            return items.sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
        } catch {
            return []
        }
    }

    public func validateRepoName(_ name: String) -> (valid: Bool, error: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return (false, "Repository name cannot be empty")
        }
        if trimmed == "." || trimmed == ".." {
            return (false, "Invalid repository name")
        }
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        if repoNameRegex.firstMatch(in: trimmed, range: range) == nil {
            return (false, "Repository name can only contain alphanumeric characters, hyphens, periods, and underscores")
        }
        return (true, nil)
    }

    public func deriveFolderName(from urlOrName: String) -> String {
        var clean = urlOrName.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasSuffix(".git") {
            clean = String(clean.dropLast(4))
        }
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lastComponent = clean.components(separatedBy: "/").last ?? clean
        if lastComponent.contains(":") {
            return lastComponent.components(separatedBy: ":").last ?? lastComponent
        }
        return lastComponent
    }

    public func cloneRepository(
        urlOrName: String,
        destinationDirectory: String,
        customFolderName: String? = nil,
        timeout: TimeInterval = 180
    ) -> CloneResult {
        let trimmedInput = urlOrName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return CloneResult(success: false, destinationPath: nil, error: "Repository URL or name cannot be empty")
        }

        let folderName: String
        if let custom = customFolderName?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            let (valid, err) = validateRepoName(custom)
            guard valid else {
                return CloneResult(success: false, destinationPath: nil, error: err ?? "Invalid folder name")
            }
            folderName = custom
        } else {
            folderName = deriveFolderName(from: trimmedInput)
        }

        let (validFolder, folderErr) = validateRepoName(folderName)
        guard validFolder else {
            return CloneResult(success: false, destinationPath: nil, error: folderErr ?? "Invalid destination folder name")
        }

        let destDir = (destinationDirectory as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destDir, isDirectory: &isDir), isDir.boolValue else {
            return CloneResult(success: false, destinationPath: nil, error: "Destination directory does not exist: \(destDir)")
        }

        let targetPath = (destDir as NSString).appendingPathComponent(folderName)
        if FileManager.default.fileExists(atPath: targetPath) {
            return CloneResult(success: false, destinationPath: nil, error: "Destination folder already exists: \(folderName)")
        }

        // Determine whether to use gh repo clone or git clone
        let isShortGitHubName = !trimmedInput.contains("://") && !trimmedInput.contains("@") && trimmedInput.contains("/")
        let ghPath = findGitHubCLI()

        let (status, _, stderr): (Int32, String, String)
        if isShortGitHubName, let gh = ghPath {
            (status, _, stderr) = runProcess(executable: gh, args: ["repo", "clone", trimmedInput, targetPath], in: destDir, timeout: timeout)
        } else {
            (status, _, stderr) = runProcess(executable: "/usr/bin/git", args: ["clone", trimmedInput, targetPath], in: destDir, timeout: timeout)
        }

        if status == 0 {
            return CloneResult(success: true, destinationPath: targetPath, error: nil)
        } else {
            let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return CloneResult(success: false, destinationPath: nil, error: err.isEmpty ? "Failed to clone repository" : err)
        }
    }

    public func createAndCloneRemoteRepository(
        name: String,
        isPrivate: Bool,
        description: String? = nil,
        addReadme: Bool = true,
        destinationDirectory: String,
        timeout: TimeInterval = 180
    ) -> CreateRemoteRepoResult {
        let (valid, nameErr) = validateRepoName(name)
        guard valid else {
            return CreateRemoteRepoResult(success: false, remoteUrl: nil, destinationPath: nil, error: nameErr)
        }

        guard let gh = findGitHubCLI() else {
            return CreateRemoteRepoResult(success: false, remoteUrl: nil, destinationPath: nil, error: "GitHub CLI (gh) is not installed")
        }

        let (authed, username) = checkAuthentication()
        guard authed, let user = username else {
            return CreateRemoteRepoResult(success: false, remoteUrl: nil, destinationPath: nil, error: "GitHub CLI is not authenticated. Please run 'gh auth login'.")
        }

        let destDir = (destinationDirectory as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destDir, isDirectory: &isDir), isDir.boolValue else {
            return CreateRemoteRepoResult(success: false, remoteUrl: nil, destinationPath: nil, error: "Destination directory does not exist: \(destDir)")
        }

        let targetPath = (destDir as NSString).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: targetPath) {
            return CreateRemoteRepoResult(success: false, remoteUrl: nil, destinationPath: nil, error: "Destination folder already exists: \(name)")
        }

        var args = ["repo", "create", name, isPrivate ? "--private" : "--public", "--clone"]
        if addReadme {
            args.append("--add-readme")
        }
        if let desc = description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
            args.append("--description")
            args.append(desc)
        }

        let (status, stdout, stderr) = runProcess(executable: gh, args: args, in: destDir, timeout: timeout)
        if status == 0 {
            let remoteUrl = "https://github.com/\(user)/\(name)"
            return CreateRemoteRepoResult(success: true, remoteUrl: remoteUrl, destinationPath: targetPath, error: nil)
        } else {
            let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let combined = !err.isEmpty ? err : out
            return CreateRemoteRepoResult(success: false, remoteUrl: nil, destinationPath: nil, error: combined.isEmpty ? "Failed to create remote repository" : combined)
        }
    }

    private func runProcess(executable: String, args: [String], in directory: String, timeout: TimeInterval = 60) -> (status: Int32, stdout: String, stderr: String) {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GH_PROMPT_DISABLED"] = "1"
        let result = ProcessRunner.run(
            executable: executable,
            arguments: args,
            currentDirectory: directory,
            environment: env,
            timeout: timeout
        )
        return (result.status, result.stdout, result.stderr)
    }
}
