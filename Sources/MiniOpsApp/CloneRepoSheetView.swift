import SwiftUI
import AppKit
import MiniOpsCore

public struct CloneRepoSheetView: View {
    public var workspacePath: String
    public var onRepoCloned: (String) -> Void
    public var onDismiss: () -> Void

    @State private var selectedTab: Int = 0 // 0: Clone Existing, 1: Create Remote
    @State private var targetDirectory: String

    // Clone Existing state
    @State private var cloneUrlOrName: String = ""
    @State private var customFolderName: String = ""
    @State private var remoteRepos: [RemoteRepoItem] = []
    @State private var repoSearchText: String = ""
    @State private var isLoadingRepos: Bool = false
    @State private var isGitHubAuthed: Bool = false
    @State private var githubUsername: String? = nil

    // Create Remote state
    @State private var newRepoName: String = ""
    @State private var newRepoIsPrivate: Bool = true
    @State private var newRepoDescription: String = ""
    @State private var newRepoAddReadme: Bool = true

    // Operation state
    @State private var isExecuting: Bool = false
    @State private var statusMessage: String = ""
    @State private var errorMessage: String? = nil

    private let githubService = GitHubService.shared

    public init(workspacePath: String, onRepoCloned: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
        self.workspacePath = workspacePath
        self._targetDirectory = State(initialValue: (workspacePath as NSString).expandingTildeInPath)
        self.onRepoCloned = onRepoCloned
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Repository Management")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Tabs
            Picker("Mode", selection: $selectedTab) {
                Label("Clone Repository", systemImage: "arrow.down.circle").tag(0)
                Label("Create & Clone Remote", systemImage: "plus.circle").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            // Error banner if any
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Spacer()
                    Button(action: { errorMessage = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
                Divider()
            }

            // Tab Content
            if selectedTab == 0 {
                cloneExistingView
            } else {
                createRemoteView
            }

            Divider()

            // Destination directory selector
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                Text("Destination:")
                    .font(.system(size: 11, weight: .medium))
                Text(targetDirectory)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Browse...") {
                    chooseDestinationDirectory()
                }
                .controlSize(.small)
                .disabled(isExecuting)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Footer / Actions
            HStack {
                if isExecuting {
                    ProgressView()
                        .controlSize(.small)
                    Text(statusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button("Cancel", action: onDismiss)
                    .disabled(isExecuting)

                if selectedTab == 0 {
                    Button("Clone Repository") {
                        executeClone(urlOrName: cloneUrlOrName, customName: customFolderName.isEmpty ? nil : customFolderName)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExecuting || cloneUrlOrName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Create & Clone") {
                        executeCreateAndClone()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExecuting || newRepoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
        }
        .frame(width: 540, height: 500)
        .onAppear {
            checkGitHubAndLoadRepos()
        }
    }

    // MARK: - Clone Existing Tab
    private var cloneExistingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // URL / Name Input
            VStack(alignment: .leading, spacing: 6) {
                Text("Clone from URL or GitHub name")
                    .font(.system(size: 11, weight: .semibold))

                HStack(spacing: 8) {
                    TextField("https://github.com/owner/repo.git or owner/repo", text: $cloneUrlOrName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    TextField("Folder (optional)", text: $customFolderName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 140)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Divider()

            // Remote GitHub Repos list
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Or select from your GitHub repositories")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    if let user = githubUsername {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("@\(user)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filter remote repositories...", text: $repoSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                if isLoadingRepos {
                    HStack {
                        Spacer()
                        ProgressView("Loading repositories from GitHub...")
                            .controlSize(.small)
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                } else if !isGitHubAuthed {
                    VStack(spacing: 6) {
                        Spacer()
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                        Text("GitHub CLI not authenticated")
                            .font(.system(size: 11, weight: .medium))
                        Text("Run 'gh auth login' to browse and clone your remote repositories with one click.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let filtered = remoteRepos.filter { item in
                        if repoSearchText.isEmpty { return true }
                        return item.nameWithOwner.localizedCaseInsensitiveContains(repoSearchText) ||
                               item.description.localizedCaseInsensitiveContains(repoSearchText)
                    }

                    if filtered.isEmpty {
                        VStack {
                            Spacer()
                            Text("No matching repositories found")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(filtered) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.isPrivate ? "lock.fill" : "globe")
                                    .font(.system(size: 10))
                                    .foregroundColor(item.isPrivate ? .orange : .secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.nameWithOwner)
                                        .font(.system(size: 11, weight: .medium))
                                    if !item.description.isEmpty {
                                        Text(item.description)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Button("Clone") {
                                    executeClone(urlOrName: item.nameWithOwner, customName: nil)
                                }
                                .controlSize(.small)
                                .disabled(isExecuting)
                            }
                            .padding(.vertical, 2)
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Create Remote Tab
    private var createRemoteView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Repository Name")
                    .font(.system(size: 11, weight: .semibold))
                TextField("my-awesome-project", text: $newRepoName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                let (valid, nameErr) = githubService.validateRepoName(newRepoName)
                if !newRepoName.isEmpty && !valid, let err = nameErr {
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Visibility")
                    .font(.system(size: 11, weight: .semibold))
                Picker("Visibility", selection: $newRepoIsPrivate) {
                    Label("Private (Only you and collaborators)", systemImage: "lock.fill").tag(true)
                    Label("Public (Anyone can view)", systemImage: "globe").tag(false)
                }
                .pickerStyle(.radioGroup)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Description (optional)")
                    .font(.system(size: 11, weight: .semibold))
                TextField("A short description of this repository", text: $newRepoDescription)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            Toggle("Initialize repository with README.md", isOn: $newRepoAddReadme)
                .font(.system(size: 11))

            Spacer()
        }
        .padding(16)
    }

    // MARK: - Actions & Logic
    private func checkGitHubAndLoadRepos() {
        let (authed, user) = githubService.checkAuthentication()
        self.isGitHubAuthed = authed
        self.githubUsername = user

        if authed {
            self.isLoadingRepos = true
            Task.detached(priority: .userInitiated) {
                let items = self.githubService.fetchUserRepositories()
                await MainActor.run {
                    self.remoteRepos = items
                    self.isLoadingRepos = false
                }
            }
        }
    }

    private func chooseDestinationDirectory() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.message = "Select Destination Folder"
        openPanel.prompt = "Select"

        if openPanel.runModal() == .OK, let url = openPanel.url {
            self.targetDirectory = url.path
        }
    }

    private func executeClone(urlOrName: String, customName: String?) {
        errorMessage = nil
        isExecuting = true
        statusMessage = "Cloning repository..."

        let destDir = targetDirectory
        Task.detached(priority: .userInitiated) {
            let result = self.githubService.cloneRepository(
                urlOrName: urlOrName,
                destinationDirectory: destDir,
                customFolderName: customName
            )

            await MainActor.run {
                self.isExecuting = false
                if result.success, let target = result.destinationPath {
                    self.onRepoCloned(target)
                } else {
                    self.errorMessage = result.error ?? "Failed to clone repository"
                }
            }
        }
    }

    private func executeCreateAndClone() {
        errorMessage = nil
        isExecuting = true
        statusMessage = "Creating remote repository on GitHub..."

        let name = newRepoName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPrivate = newRepoIsPrivate
        let desc = newRepoDescription.isEmpty ? nil : newRepoDescription
        let addReadme = newRepoAddReadme
        let destDir = targetDirectory

        Task.detached(priority: .userInitiated) {
            let result = self.githubService.createAndCloneRemoteRepository(
                name: name,
                isPrivate: isPrivate,
                description: desc,
                addReadme: addReadme,
                destinationDirectory: destDir
            )

            await MainActor.run {
                self.isExecuting = false
                if result.success, let target = result.destinationPath {
                    self.onRepoCloned(target)
                } else {
                    self.errorMessage = result.error ?? "Failed to create remote repository"
                }
            }
        }
    }
}
