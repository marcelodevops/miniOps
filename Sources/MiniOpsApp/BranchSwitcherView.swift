import SwiftUI
import MiniOpsCore

public struct BranchSwitcherView: View {
    public let repoPath: String
    public let currentBranch: String
    public let onBranchChanged: () -> Void

    @State private var availableBranches: [String] = []
    @State private var isShowingNewBranchSheet: Bool = false
    @State private var newBranchName: String = ""
    @State private var errorMessage: String?

    public init(repoPath: String, currentBranch: String, onBranchChanged: @escaping () -> Void) {
        self.repoPath = repoPath
        self.currentBranch = currentBranch
        self.onBranchChanged = onBranchChanged
    }

    public var body: some View {
        Menu {
            Section("Current Branch") {
                Label(currentBranch, systemImage: "checkmark")
            }

            Section("Switch Branch") {
                ForEach(availableBranches.filter { $0 != currentBranch }, id: \.self) { branch in
                    Button(branch) {
                        switchBranch(to: branch)
                    }
                }
            }

            Divider()

            Button("Create New Branch...") {
                newBranchName = ""
                errorMessage = nil
                isShowingNewBranchSheet = true
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                Text(currentBranch)
                    .font(.system(size: 11, design: .monospaced))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
        .menuStyle(.borderlessButton)
        .onAppear {
            loadBranches()
        }
        .sheet(isPresented: $isShowingNewBranchSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Create New Branch")
                    .font(.headline)

                TextField("Branch Name (e.g. feat/my-feature)", text: $newBranchName)
                    .textFieldStyle(.roundedBorder)

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack {
                    Button("Cancel") {
                        isShowingNewBranchSheet = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Create and Checkout") {
                        createNewBranch()
                    }
                    .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 380)
        }
    }

    private func loadBranches() {
        availableBranches = GitService.shared.listBranches(repoPath: repoPath)
    }

    private func switchBranch(to branch: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let res = GitService.shared.checkout(repoPath: repoPath, branch: branch)
            DispatchQueue.main.async {
                if res.success {
                    onBranchChanged()
                    loadBranches()
                } else {
                    errorMessage = res.error
                }
            }
        }
    }

    private func createNewBranch() {
        let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.global(qos: .userInitiated).async {
            let res = GitService.shared.createBranch(repoPath: repoPath, branchName: name)
            DispatchQueue.main.async {
                if res.success {
                    isShowingNewBranchSheet = false
                    onBranchChanged()
                    loadBranches()
                } else {
                    errorMessage = res.error
                }
            }
        }
    }
}
