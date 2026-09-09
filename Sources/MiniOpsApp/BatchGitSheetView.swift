import SwiftUI
import MiniOpsCore

public struct BatchGitSheetView: View {
    public let repos: [RepoInfo]
    public let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var isProcessing: Bool = false
    @State private var currentAction: String = "fetch"
    @State private var batchResult: BatchGitResult?

    public init(repos: [RepoInfo], onComplete: @escaping () -> Void) {
        self.repos = repos
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "square.stack.3d.up")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                Text("Batch Git Operations")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }

            Text("Execute a synchronized Git action across all \(repos.count) repositories in your workspace.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            HStack(spacing: 12) {
                Button(action: { runBatch(action: "fetch") }) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.title3)
                        Text("Fetch All")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                }
                .disabled(isProcessing)

                Button(action: { runBatch(action: "pull") }) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.title3)
                        Text("Pull Clean")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                }
                .disabled(isProcessing)

                Button(action: { runBatch(action: "reconcile") }) {
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.seal")
                            .font(.title3)
                        Text("Reconcile All")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                }
                .disabled(isProcessing)
            }

            if isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Executing batch \(currentAction)...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            if let result = batchResult {
                Divider()
                HStack {
                    Text("Result: \(result.successCount) succeeded, \(result.failureCount) failed / skipped")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(result.failureCount == 0 ? .green : .orange)
                    Spacer()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(repos) { repo in
                            if let opRes = result.results[repo.path] {
                                HStack(spacing: 6) {
                                    Image(systemName: opRes.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundColor(opRes.success ? .green : .orange)
                                        .font(.system(size: 11))
                                    Text(repo.name)
                                        .font(.system(size: 11, weight: .semibold))
                                    Spacer()
                                    Text(opRes.success ? (opRes.output.isEmpty ? "OK" : opRes.output) : (opRes.error ?? "Failed"))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func runBatch(action: String) {
        currentAction = action
        isProcessing = true
        batchResult = nil

        let paths = repos.map { $0.path }
        DispatchQueue.global(qos: .userInitiated).async {
            let res = GitService.shared.batchGit(action: action, repoPaths: paths)
            DispatchQueue.main.async {
                isProcessing = false
                batchResult = res
                onComplete()
            }
        }
    }
}
