import SwiftUI
import AppKit
import MiniOpsCore

public struct SettingsView: View {
    @ObservedObject public var viewModel: WorkspaceViewModel
    @State private var selectedTab: SettingsTab = .hiddenRepos

    public enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case hiddenRepos = "Repositories"
        case credentials = "Credentials"
        case integrations = "Integrations"

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
                Label("Credentials", systemImage: "key.fill").tag(SettingsTab.credentials)
                Label("Herdr", systemImage: "cable.connector.horizontal").tag(SettingsTab.integrations)
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
            case .credentials:
                CredentialsSettingsTab()
            case .integrations:
                HerdrIntegrationsTab()
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 440, idealHeight: 500)
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
    @State private var auditMessage: String?
    @State private var isAuditWarning: Bool = false
    @State private var pendingImportJSON: String?
    @State private var pendingImportFilename: String?
    @State private var pendingImportPreview: SettingsImportPreview?

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

                // Tickets Directory
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tickets Directory")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)

                    HStack {
                        Image(systemName: "ticket")
                            .foregroundColor(.secondary)
                        Text(viewModel.ticketsPath.isEmpty ? "Default (workspace/tickets)" : viewModel.ticketsPath)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(viewModel.ticketsPath.isEmpty ? .secondary : .primary)
                        Spacer()
                        if !viewModel.ticketsPath.isEmpty {
                            Button("Reset") {
                                _ = viewModel.setTicketsPath("")
                                auditMessage = "Reset tickets directory to workspace default."
                                isAuditWarning = false
                            }
                        }
                        Button("Change…") {
                            chooseTicketsDirectory()
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

                // Backup & Audit
                VStack(alignment: .leading, spacing: 8) {
                    Text("Settings Backup & Audit")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        Button("Export Settings…") {
                            exportSettings()
                        }
                        Button("Import Settings…") {
                            importSettings()
                        }
                        Button("Audit Settings") {
                            runSettingsAudit()
                        }
                    }

                    if let preview = pendingImportPreview, let filename = pendingImportFilename {
                        SettingsImportPreviewView(
                            filename: filename,
                            preview: preview,
                            onApply: { overwrite in
                                applyImport(overwriteConflicts: overwrite)
                            },
                            onCancel: {
                                cancelImportPreview()
                            }
                        )
                    }

                    if let auditMsg = auditMessage {
                        HStack(spacing: 6) {
                            Image(systemName: isAuditWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundColor(isAuditWarning ? .orange : .green)
                            Text(auditMsg)
                                .font(.system(size: 11))
                                .foregroundColor(isAuditWarning ? .orange : .primary)
                            Spacer()
                            Button(action: { auditMessage = nil }) {
                                Image(systemName: "xmark").font(.system(size: 10))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(8)
                        .background(isAuditWarning ? Color.orange.opacity(0.1) : Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                }

                Spacer()
            }
            .padding(20)
        }
    }

    private func chooseTicketsDirectory() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.message = "Choose a Tickets Directory"
        openPanel.prompt = "Select Tickets Folder"

        if openPanel.runModal() == .OK, let url = openPanel.url {
            let res = viewModel.setTicketsPath(url.path)
            if !res.success {
                auditMessage = res.error
                isAuditWarning = true
            } else {
                auditMessage = "Tickets directory updated to: \(url.path)"
                isAuditWarning = false
            }
        }
    }

    private func exportSettings() {
        guard let json = viewModel.exportSettingsJSON() else {
            auditMessage = "Failed to export settings."
            isAuditWarning = true
            return
        }
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "miniops-settings.json"
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try json.write(to: url, atomically: true, encoding: .utf8)
                auditMessage = "Settings exported successfully to \(url.lastPathComponent)."
                isAuditWarning = false
            } catch {
                auditMessage = "Failed to save file: \(error.localizedDescription)"
                isAuditWarning = true
            }
        }
    }

    private func importSettings() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.message = "Choose a settings JSON file to import"
        if openPanel.runModal() == .OK, let url = openPanel.url {
            do {
                let json = try String(contentsOf: url, encoding: .utf8)
                let (preview, err) = viewModel.previewSettingsImport(json)
                if let err = err {
                    auditMessage = err
                    isAuditWarning = true
                    cancelImportPreview()
                    return
                }
                guard let preview = preview else {
                    auditMessage = "Failed to parse settings JSON."
                    isAuditWarning = true
                    cancelImportPreview()
                    return
                }
                if !preview.validationErrors.isEmpty {
                    auditMessage = "Validation failed: " + preview.validationErrors.joined(separator: "; ")
                    isAuditWarning = true
                    cancelImportPreview()
                    return
                }
                self.pendingImportJSON = json
                self.pendingImportFilename = url.lastPathComponent
                self.pendingImportPreview = preview
                self.auditMessage = nil
            } catch {
                auditMessage = "Could not read file: \(error.localizedDescription)"
                isAuditWarning = true
                cancelImportPreview()
            }
        }
    }

    private func cancelImportPreview() {
        pendingImportJSON = nil
        pendingImportFilename = nil
        pendingImportPreview = nil
    }

    private func applyImport(overwriteConflicts: Bool) {
        guard let json = pendingImportJSON else { return }
        let res = viewModel.importSettingsJSON(json, overwriteConflicts: overwriteConflicts)
        cancelImportPreview()
        if res.success {
            var detail = "Settings imported successfully (backup created at state.bak.json)."
            if !overwriteConflicts {
                detail += " Existing values were preserved on conflict."
            } else {
                detail += " Conflicting values were overwritten."
            }
            if let prev = res.preview, prev.hasConflicts {
                detail += " Merged \(prev.newHiddenRepos.count) hidden and \(prev.newCustomRepos.count) custom repos."
            }
            auditMessage = detail
            isAuditWarning = false
        } else {
            auditMessage = res.error ?? "Failed to import settings."
            isAuditWarning = true
        }
    }

    private func runSettingsAudit() {
        let warnings = viewModel.auditSettings()
        if warnings.isEmpty {
            auditMessage = "All configured workspace, ticket, and repository paths are healthy and valid."
            isAuditWarning = false
        } else {
            auditMessage = "Audit found \(warnings.count) issue(s): " + warnings.joined(separator: "; ")
            isAuditWarning = true
        }
    }
}

private struct SettingsImportPreviewView: View {
    let filename: String
    let preview: SettingsImportPreview
    let onApply: (Bool) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: preview.hasConflicts ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundColor(preview.hasConflicts ? .orange : .green)
                    .font(.system(size: 13))
                Text("Pre-Import Review: \(filename)")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
            }

            // Conflict / status banner
            if preview.hasConflicts {
                Text("Conflicts detected with current settings. Existing values will be preserved by default unless you choose to overwrite them.")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(6)
            } else {
                Text("No conflicts detected. All configuration settings are compatible and will be imported cleanly.")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(6)
            }

            // Conflict & mapping details
            VStack(alignment: .leading, spacing: 6) {
                // Workspace conflict
                if let ws = preview.workspaceConflict {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workspace Conflict")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Current: \(ws.currentValue)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("Imported: \(ws.importedValue)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.primary)
                        Text("• Will preserve current workspace by default")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                }

                // Integration conflicts
                if !preview.integrationConflicts.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Integration Conflicts (\(preview.integrationConflicts.count))")
                            .font(.system(size: 11, weight: .semibold))
                        ForEach(preview.integrationConflicts, id: \.field) { conflict in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(conflict.field):")
                                    .font(.system(size: 10, weight: .medium))
                                Text("  Current: \(conflict.currentValue)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text("  Imported: \(conflict.importedValue)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                        }
                        Text("• Will preserve current values by default")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                }

                // Repositories summary
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repository Merging")
                        .font(.system(size: 11, weight: .semibold))
                    HStack(spacing: 12) {
                        Text("Custom repos: +\(preview.newCustomRepos.count) new, \(preview.preservedCustomRepos.count) preserved")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("Hidden repos: +\(preview.newHiddenRepos.count) new, \(preview.preservedHiddenRepos.count) preserved")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)

                // Layouts summary
                if !preview.layoutConflicts.isEmpty || !preview.newLayouts.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workbench Layouts")
                            .font(.system(size: 11, weight: .semibold))
                        HStack(spacing: 12) {
                            if !preview.layoutConflicts.isEmpty {
                                Text("\(preview.layoutConflicts.count) conflicting layout(s) (preserved by default)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            if !preview.newLayouts.isEmpty {
                                Text("+\(preview.newLayouts.count) new layout(s)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                }

                // Backup notice
                HStack(spacing: 4) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                    Text("Destination state is automatically backed up to state.bak.json. Import will abort before mutating if backup fails.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }

            // Action Buttons
            HStack(spacing: 8) {
                if preview.hasConflicts {
                    Button("Apply Import (Preserve Conflicts)") {
                        onApply(false)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Overwrite Conflicts") {
                        onApply(true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Apply Import") {
                        onApply(false)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(preview.hasConflicts ? Color.orange.opacity(0.4) : Color.accentColor.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(8)
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

private struct CredentialsSettingsTab: View {
    @State private var jiraBaseURL: String = ""
    @State private var jiraEmail: String = ""
    @State private var jiraToken: String = ""
    @State private var githubUsername: String = ""
    @State private var githubToken: String = ""
    @State private var storedJiraToken: String?
    @State private var storedGitHubToken: String?
    @State private var isTestingJira: Bool = false
    @State private var isTestingGitHub: Bool = false
    @State private var statusMessage: String?
    @State private var isStatusError: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Credentials")
                        .font(.system(size: 13, weight: .bold))
                    Text("Tokens are stored in the macOS Keychain. Only the host, email and username are written to the miniOps state file.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if let statusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: isStatusError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(isStatusError ? .red : .green)
                        Text(statusMessage)
                            .font(.system(size: 11))
                            .foregroundColor(isStatusError ? .red : .primary)
                        Spacer()
                        Button(action: { self.statusMessage = nil }) {
                            Image(systemName: "xmark").font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(8)
                    .background(isStatusError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                    .cornerRadius(6)
                }

                // Jira
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "ticket")
                            .foregroundColor(.accentColor)
                        Text("Jira")
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                        CredentialBadge(storedToken: storedJiraToken)
                    }

                    LabeledField(label: "Site URL", placeholder: "https://your-org.atlassian.net") {
                        TextField("https://your-org.atlassian.net", text: $jiraBaseURL)
                    }
                    LabeledField(label: "Email", placeholder: "you@example.com") {
                        TextField("you@example.com", text: $jiraEmail)
                    }
                    LabeledField(label: "API Token", placeholder: "Atlassian API token") {
                        SecureField(storedJiraToken == nil ? "Atlassian API token" : "Enter a new token to replace the stored one", text: $jiraToken)
                    }

                    HStack {
                        Button("Save Jira Credentials") { saveJira() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button(isTestingJira ? "Testing…" : "Test Connection & Sync") { testAndSyncJira() }
                            .controlSize(.small)
                            .disabled(isTestingJira || (storedJiraToken == nil && jiraToken.isEmpty))
                        Button("Clear Token") { clearToken(.jira) }
                            .controlSize(.small)
                            .disabled(storedJiraToken == nil)
                        Spacer()
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // GitHub
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .foregroundColor(.accentColor)
                        Text("GitHub")
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                        CredentialBadge(storedToken: storedGitHubToken)
                    }

                    LabeledField(label: "Username", placeholder: "octocat") {
                        TextField("octocat", text: $githubUsername)
                    }
                    LabeledField(label: "Personal Access Token", placeholder: "ghp_…") {
                        SecureField(storedGitHubToken == nil ? "ghp_…" : "Enter a new token to replace the stored one", text: $githubToken)
                    }

                    HStack {
                        Button("Save GitHub Credentials") { saveGitHub() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button(isTestingGitHub ? "Testing…" : "Test Connection") { testGitHub() }
                            .controlSize(.small)
                            .disabled(isTestingGitHub || (storedGitHubToken == nil && githubToken.isEmpty))
                        Button("Clear Token") { clearToken(.github) }
                            .controlSize(.small)
                            .disabled(storedGitHubToken == nil)
                        Spacer()
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                Spacer()
            }
            .padding(20)
        }
        .onAppear { load() }
    }

    private func load() {
        let settings = WorkspaceStateStore.shared.getIntegrationSettings()
        jiraBaseURL = settings.jiraBaseURL
        jiraEmail = settings.jiraEmail
        githubUsername = settings.githubUsername
        storedJiraToken = CredentialStore.shared.maskedSecret(for: .jira)
        storedGitHubToken = CredentialStore.shared.maskedSecret(for: .github)
    }

    private func persistNonSecrets() {
        var settings = WorkspaceStateStore.shared.getIntegrationSettings()
        settings.jiraBaseURL = jiraBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.jiraEmail = jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.githubUsername = githubUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        WorkspaceStateStore.shared.saveIntegrationSettings(settings)
    }

    private func saveJira() {
        persistNonSecrets()
        if jiraToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            report("Jira site and email saved. Existing token left unchanged.", isError: false)
        } else if CredentialStore.shared.saveSecret(jiraToken, for: .jira) {
            report("Jira credentials saved to the Keychain.", isError: false)
        } else {
            report("Could not write the Jira token to the Keychain.", isError: true)
        }
        jiraToken = ""
        load()
    }

    private func testAndSyncJira() {
        persistNonSecrets()
        if !jiraToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = CredentialStore.shared.saveSecret(jiraToken, for: .jira)
            jiraToken = ""
            load()
        }

        guard let token = CredentialStore.shared.readSecret(for: .jira), !token.isEmpty else {
            report("No Jira API token stored to test.", isError: true)
            return
        }

        isTestingJira = true
        report("Verifying credentials with Jira…", isError: false)

        let targetBase = jiraBaseURL
        let targetEmail = jiraEmail
        let wsPath = WorkspaceStateStore.shared.getAppState().lastWorkspacePath ?? "~/repos"

        Task {
            let verify = await JiraService.shared.verifyCredentials(baseURL: targetBase, email: targetEmail, token: token)
            if !verify.success {
                await MainActor.run {
                    self.isTestingJira = false
                    self.report(verify.error ?? "Jira authentication failed", isError: true)
                }
                return
            }

            let sync = await JiraService.shared.syncTickets(workspacePath: wsPath)
            await MainActor.run {
                self.isTestingJira = false
                let userLabel = verify.displayName ?? verify.email ?? targetEmail
                if sync.success {
                    self.report("Connected as \(userLabel). Synced \(sync.ticketCount) ticket(s).", isError: false)
                } else {
                    self.report("Connected as \(userLabel), but sync returned: \(sync.error ?? "error")", isError: true)
                }
            }
        }
    }

    private func saveGitHub() {
        persistNonSecrets()
        if githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            report("GitHub username saved. Existing token left unchanged.", isError: false)
        } else if CredentialStore.shared.saveSecret(githubToken, for: .github) {
            report("GitHub credentials saved to the Keychain.", isError: false)
        } else {
            report("Could not write the GitHub token to the Keychain.", isError: true)
        }
        githubToken = ""
        load()
    }

    private func testGitHub() {
        persistNonSecrets()
        if !githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = CredentialStore.shared.saveSecret(githubToken, for: .github)
            githubToken = ""
            load()
        }

        guard let token = CredentialStore.shared.readSecret(for: .github), !token.isEmpty else {
            report("No GitHub token stored to test.", isError: true)
            return
        }

        isTestingGitHub = true
        report("Verifying credentials with GitHub…", isError: false)

        let targetUser = githubUsername
        Task {
            let verify = await GitHubService.shared.verifyCredentials(username: targetUser, token: token)
            await MainActor.run {
                self.isTestingGitHub = false
                if verify.success {
                    let userText = verify.authenticatedUser.map { " for user '\($0)'" } ?? ""
                    self.report("GitHub connection verified successfully\(userText).", isError: false)
                } else {
                    self.report(verify.error ?? "GitHub verification failed.", isError: true)
                }
            }
        }
    }

    private func clearToken(_ account: CredentialAccount) {
        if CredentialStore.shared.deleteSecret(for: account) {
            report("\(account.displayName) token removed from the Keychain.", isError: false)
        } else {
            report("Could not remove the \(account.displayName) token.", isError: true)
        }
        load()
    }

    private func report(_ message: String, isError: Bool) {
        statusMessage = message
        isStatusError = isError
    }
}

private struct CredentialBadge: View {
    let storedToken: String?

    var body: some View {
        Text(storedToken ?? "No token stored")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(storedToken == nil ? Color.secondary.opacity(0.15) : Color.green.opacity(0.15))
            )
            .foregroundColor(storedToken == nil ? .secondary : .green)
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    let placeholder: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 150, alignment: .leading)
            content
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
        }
    }
}

private struct HerdrIntegrationsTab: View {
    @State private var herdrStatus = HerdrService.shared.getHerdrStatus()
    @State private var integrations: [HerdrIntegrationInfo] = HerdrService.shared.getIntegrations()
    @State private var actionMessage: String?
    @State private var isActionError: Bool = false
    @State private var isProcessing: Bool = false
    @State private var herdrModeEnabled: Bool = WorkspaceStateStore.shared.getIntegrationSettings().herdrModeEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Section 1: Herdr Daemon Status
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Herdr Terminal Workspace Manager")
                                .font(.system(size: 13, weight: .bold))
                            Text("Automated workspace and agent multiplexer running via Unix domain socket.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Refresh") {
                            refreshAll()
                        }
                        .controlSize(.small)
                    }

                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(herdrStatus.isRunning ? Color.green : Color.orange)
                                .frame(width: 9, height: 9)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(herdrStatus.isRunning ? "Server Running" : "Server Not Detected")
                                    .font(.system(size: 12, weight: .bold))
                                if let ver = herdrStatus.version {
                                    Text("Version: \(ver)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)

                        if let socket = herdrStatus.socketPath {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("API Socket")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                Text(socket)
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }

                Divider()

                // Section 2: Herdr Mode
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $herdrModeEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Herdr Mode")
                                .font(.system(size: 13, weight: .bold))
                            Text("Open a Herdr session in the embedded terminal by default instead of a plain login shell. Each repository attaches its own session named after the repository.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.switch)
                    .onChange(of: herdrModeEnabled) { newValue in
                        WorkspaceStateStore.shared.setHerdrModeEnabled(newValue)
                        // Existing terminals keep their current process; drop them so the
                        // next terminal that opens uses the new launch mode.
                        TerminalSessionManager.shared.resetAllSessions()
                        isActionError = false
                        actionMessage = newValue
                            ? "Herdr mode enabled. Terminals opened from now on attach a Herdr session."
                            : "Herdr mode disabled. Terminals opened from now on use your login shell."
                    }

                    if herdrModeEnabled && HerdrService.shared.findExecutable() == nil {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("The herdr executable was not found — terminals fall back to your login shell.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Divider()

                // Section 3: Agent Hook Integrations
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Agent Lifecycle Hooks (\(integrations.count))")
                                .font(.system(size: 13, weight: .bold))
                            Text("Hooks report real-time agent lifecycle states (working, idle, blocked at prompts) to Herdr and miniOps.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()

                        Button(action: installRecommendedHooks) {
                            Label("Install Recommended", systemImage: "arrow.down.circle")
                                .font(.system(size: 11))
                        }
                        .controlSize(.small)
                        .disabled(isProcessing)
                    }

                    if let msg = actionMessage {
                        HStack(spacing: 6) {
                            Image(systemName: isActionError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundColor(isActionError ? .red : .green)
                            Text(msg)
                                .font(.system(size: 11))
                                .foregroundColor(isActionError ? .red : .primary)
                            Spacer()
                            Button(action: { actionMessage = nil }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(8)
                        .background(isActionError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }

                    VStack(spacing: 6) {
                        ForEach(integrations) { item in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(item.isInstalled ? Color.green : Color.secondary.opacity(0.4))
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(item.displayName)
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("(\(item.target))")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }

                                    if let path = item.hookPath {
                                        Text(path)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }

                                Spacer()

                                Text(item.statusText)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(item.isInstalled ? Color.green.opacity(0.15) : Color.secondary.opacity(0.15))
                                    )
                                    .foregroundColor(item.isInstalled ? .green : .secondary)

                                if item.isInstalled {
                                    Button(action: {
                                        uninstallHook(target: item.target)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundColor(.secondary)
                                    .help("Uninstall \(item.displayName) hook")
                                    .disabled(isProcessing)
                                } else {
                                    Button("Install") {
                                        installHook(target: item.target)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(isProcessing)
                                }
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
        }
        .onAppear {
            refreshAll()
        }
    }

    private func refreshAll() {
        herdrStatus = HerdrService.shared.getHerdrStatus()
        integrations = HerdrService.shared.getIntegrations()
        herdrModeEnabled = WorkspaceStateStore.shared.getIntegrationSettings().herdrModeEnabled
    }

    private func installHook(target: String) {
        isProcessing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let res = HerdrService.shared.installIntegration(target: target)
            DispatchQueue.main.async {
                self.isProcessing = false
                self.isActionError = !res.success
                self.actionMessage = res.message
                self.refreshAll()
            }
        }
    }

    private func uninstallHook(target: String) {
        isProcessing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let res = HerdrService.shared.uninstallIntegration(target: target)
            DispatchQueue.main.async {
                self.isProcessing = false
                self.isActionError = !res.success
                self.actionMessage = res.message
                self.refreshAll()
            }
        }
    }

    private func installRecommendedHooks() {
        isProcessing = true
        let targets = ["antigravity-cli", "claude", "codex", "copilot"]
        DispatchQueue.global(qos: .userInitiated).async {
            var messages: [String] = []
            for t in targets {
                let res = HerdrService.shared.installIntegration(target: t)
                messages.append("\(t): \(res.success ? "installed" : "failed")")
            }
            DispatchQueue.main.async {
                self.isProcessing = false
                self.isActionError = false
                self.actionMessage = messages.joined(separator: ", ")
                self.refreshAll()
            }
        }
    }
}
