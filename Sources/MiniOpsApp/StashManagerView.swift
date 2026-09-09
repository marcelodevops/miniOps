import SwiftUI
import AppKit
import MiniOpsCore

public struct StashManagerView: View {
    public let repoPath: String
    public let onStashChanged: () -> Void

    @State private var stashes: [GitStashItem] = []
    @State private var selectedStashRef: String?
    @State private var stashDiff: String = ""
    @State private var newStashMessage: String = ""
    @State private var statusMessage: String?
    @State private var isErrorMessage: Bool = false
    @State private var isProcessing: Bool = false

    public init(repoPath: String, onStashChanged: @escaping () -> Void) {
        self.repoPath = repoPath
        self.onStashChanged = onStashChanged
    }

    public var body: some View {
        HSplitView {
            // Left: Stash list & creation
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("Git Stashes (\(stashes.count))")
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    Button(action: reloadStashes) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Create new stash section
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Stash message (optional)", text: $newStashMessage)
                        .textFieldStyle(.roundedBorder)

                    Button(action: createStash) {
                        HStack(spacing: 4) {
                            Image(systemName: "tray.and.arrow.down")
                            Text("Stash Changes")
                        }
                    }
                    .disabled(isProcessing)
                }
                .padding(10)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Stashes list
                if stashes.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "archivebox")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("No stashes recorded")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List(stashes) { stash in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(stash.ref)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.accentColor)
                                Spacer()
                                Text(stash.date)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            Text(stash.message)
                                .font(.system(size: 11))
                                .lineLimit(2)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedStashRef = stash.ref
                            loadStashDiff(ref: stash.ref)
                        }
                    }
                    .listStyle(.plain)
                }

                if let msg = statusMessage {
                    Divider()
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(isErrorMessage ? .red : .green)
                        .padding(8)
                }
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 400)

            // Right: Stash diff & actions
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if let ref = selectedStashRef {
                        Text("Stash: \(ref)")
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                        Button(action: popSelectedStash) {
                            HStack(spacing: 4) {
                                Image(systemName: "tray.and.arrow.up")
                                Text("Pop Stash")
                            }
                            .font(.system(size: 11))
                        }
                        .disabled(isProcessing)
                    } else {
                        Text("Select a stash to inspect")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                if stashDiff.isEmpty {
                    VStack {
                        Spacer()
                        Text("No stash selected")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(stashDiff.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                                Text(line.isEmpty ? " " : line)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(diffLineColor(line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                }
            }
            .frame(minWidth: 300, maxWidth: .infinity)
        }
        .onAppear {
            reloadStashes()
        }
    }

    private func reloadStashes() {
        stashes = GitService.shared.listStashes(repoPath: repoPath)
        if let first = stashes.first {
            selectedStashRef = first.ref
            loadStashDiff(ref: first.ref)
        } else {
            selectedStashRef = nil
            stashDiff = ""
        }
    }

    private func loadStashDiff(ref: String) {
        stashDiff = GitService.shared.showStash(repoPath: repoPath, stashRef: ref)
    }

    private func createStash() {
        isProcessing = true
        statusMessage = "Creating stash..."
        isErrorMessage = false

        DispatchQueue.global(qos: .userInitiated).async {
            let res = GitService.shared.stash(repoPath: repoPath, message: newStashMessage)
            DispatchQueue.main.async {
                isProcessing = false
                if res.success {
                    statusMessage = "Stash created successfully."
                    isErrorMessage = false
                    newStashMessage = ""
                    reloadStashes()
                    onStashChanged()
                } else {
                    statusMessage = res.error ?? "Stash failed."
                    isErrorMessage = true
                }
            }
        }
    }

    private func popSelectedStash() {
        guard let ref = selectedStashRef else { return }
        isProcessing = true
        statusMessage = "Popping stash \(ref)..."
        isErrorMessage = false

        DispatchQueue.global(qos: .userInitiated).async {
            let res = GitService.shared.popStash(repoPath: repoPath, stashRef: ref)
            DispatchQueue.main.async {
                isProcessing = false
                if res.success {
                    statusMessage = "Stash popped successfully."
                    isErrorMessage = false
                    reloadStashes()
                    onStashChanged()
                } else {
                    statusMessage = res.error ?? "Pop failed."
                    isErrorMessage = true
                }
            }
        }
    }

    private func diffLineColor(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return .green
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return .red
        } else if line.hasPrefix("@@") {
            return .accentColor
        }
        return .secondary
    }
}
