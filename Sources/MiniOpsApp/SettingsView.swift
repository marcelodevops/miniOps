import SwiftUI
import AppKit
import MiniOpsCore

public struct SettingsView: View {
    @ObservedObject public var viewModel: WorkspaceViewModel
    @State private var selectedTab: SettingsTab = .hiddenRepos

    public enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case hiddenRepos = "Repositories"

        public var id: String { rawValue }
    }

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Tab Picker Header
            Picker("", selection: $selectedTab) {
                Label("General", systemImage: "gear").tag(SettingsTab.general)
                Label("Repositories", systemImage: "folder.badge.gearshape").tag(SettingsTab.hiddenRepos)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Tab Content
            switch selectedTab {
            case .general:
                GeneralSettingsTab(viewModel: viewModel)
            case .hiddenRepos:
                RepositoriesSettingsTab(viewModel: viewModel)
            }
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 400, idealHeight: 460)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

public struct SettingsSheetContainer: View {
    @ObservedObject public var viewModel: WorkspaceViewModel
    @Binding public var isPresented: Bool

    public init(viewModel: WorkspaceViewModel, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            SettingsView(viewModel: viewModel)
        }
        .frame(minWidth: 540, idealWidth: 600, minHeight: 460, idealHeight: 520)
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Workspace Root
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workspace Directory")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)

                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.secondary)
                        Text(viewModel.workspacePath)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Change…") {
                            viewModel.chooseWorkspaceDirectory()
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                // Stats Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overview")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)

                    HStack(spacing: 12) {
                        StatCard(
                            title: "Active Repositories",
                            value: "\(viewModel.repositories.count)",
                            icon: "folder.fill",
                            color: .accentColor
                        )

                        StatCard(
                            title: "Hidden Repositories",
                            value: "\(viewModel.hiddenRepoPaths.count)",
                            icon: "eye.slash.fill",
                            color: .orange
                        )

                        StatCard(
                            title: "Active Agents",
                            value: "\(viewModel.activeAgents.count)",
                            icon: "cpu",
                            color: .green
                        )
                    }
                }

                // Quick Actions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actions")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)

                    HStack {
                        Button("Rescan Workspace Repositories") {
                            viewModel.refreshRepositories()
                        }

                        if !viewModel.hiddenRepoPaths.isEmpty {
                            Button("Unhide All Repositories") {
                                viewModel.unhideAllRepos()
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
        }
    }
}

private struct RepositoriesSettingsTab: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @State private var importStatusMessage: String?
    @State private var isImportError: Bool = false

    var sortedHiddenPaths: [String] {
        viewModel.hiddenRepoPaths.sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Section 1: Hidden Repositories
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hidden Repositories (\(sortedHiddenPaths.count))")
                                .font(.system(size: 13, weight: .bold))
                            Text("Repositories hidden from the sidebar. You can show them again or re-import them.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if !sortedHiddenPaths.isEmpty {
                            Button(action: {
                                viewModel.unhideAllRepos()
                            }) {
                                Label("Unhide All", systemImage: "eye")
                                    .font(.system(size: 11))
                            }
                        }
                    }

                    if sortedHiddenPaths.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "eye")
                                    .font(.system(size: 28))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text("No hidden repositories")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text("Right-click any repository in the sidebar and choose 'Hide Repository' to hide it.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary.opacity(0.8))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(24)
                            Spacer()
                        }
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(sortedHiddenPaths, id: \.self) { path in
                                HiddenRepoRow(
                                    path: path,
                                    onUnhide: {
                                        viewModel.unhideRepo(path: path)
                                    },
                                    onReimport: {
                                        let ok = viewModel.reimportRepo(path: path)
                                        if ok {
                                            importStatusMessage = "Re-imported and selected '\(URL(fileURLWithPath: path).lastPathComponent)'."
                                            isImportError = false
                                        } else {
                                            importStatusMessage = "Could not find valid .git repository at: \(path)"
                                            isImportError = true
                                        }
                                    }
                                )
                            }
                        }
                    }
                }

                Divider()

                // Section 2: Re-import from Disk
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Re-import Repository from Disk")
                            .font(.system(size: 13, weight: .bold))
                        Text("Select any Git repository folder on your computer to import or re-import into miniOps.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Button(action: chooseAndImportRepo) {
                            Label("Browse & Re-import Repository…", systemImage: "plus.rectangle.on.folder")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .controlSize(.regular)

                        Spacer()
                    }

                    if let message = importStatusMessage {
                        HStack(spacing: 6) {
                            Image(systemName: isImportError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundColor(isImportError ? .red : .green)
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundColor(isImportError ? .red : .primary)
                            Spacer()
                            Button(action: { importStatusMessage = nil }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(8)
                        .background(isImportError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                }

                Spacer()
            }
            .padding(20)
        }
    }

    private func chooseAndImportRepo() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.message = "Choose a Git repository to import or re-import"
        openPanel.prompt = "Import Repository"

        if openPanel.runModal() == .OK, let url = openPanel.url {
            let path = url.path
            let gitURL = url.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            let hasGit = FileManager.default.fileExists(atPath: gitURL.path, isDirectory: &isDir)

            if !hasGit {
                importStatusMessage = "Selected folder '\(url.lastPathComponent)' does not contain a .git directory."
                isImportError = true
                return
            }

            let ok = viewModel.reimportRepo(path: path)
            if ok {
                importStatusMessage = "Successfully re-imported '\(url.lastPathComponent)'."
                isImportError = false
            } else {
                importStatusMessage = "Failed to import repository at: \(path)"
                isImportError = true
            }
        }
    }
}

private struct HiddenRepoRow: View {
    let path: String
    let onUnhide: () -> Void
    let onReimport: () -> Void

    var repoName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var existsOnDisk: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.minus")
                .font(.system(size: 14))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(repoName)
                        .font(.system(size: 12, weight: .semibold))
                    if !existsOnDisk {
                        Text("Missing on disk")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red.opacity(0.15)))
                    }
                }

                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: onUnhide) {
                Label("Show", systemImage: "eye")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Unhide this repository and show it in the sidebar")

            Button(action: onReimport) {
                Label("Re-import", systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Re-import and select this repository in the workspace")
            .disabled(!existsOnDisk)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 12))
                Spacer()
            }

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
