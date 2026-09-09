import SwiftUI
import MiniOpsCore

public struct RepoNotesView: View {
    public let repoPath: String
    @State private var noteContent: String = ""
    @State private var isSaved: Bool = true

    public init(repoPath: String) {
        self.repoPath = repoPath
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "note.text")
                    .foregroundColor(.accentColor)
                Text("Repo Runbook & Notes")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                if !isSaved {
                    Text("Auto-saving...")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            TextEditor(text: $noteContent)
                .font(.system(size: 12, design: .monospaced))
                .padding(6)
                .onChange(of: noteContent) { _, newValue in
                    isSaved = false
                    NotesService.shared.saveNote(for: repoPath, note: newValue)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isSaved = true
                    }
                }
        }
        .onAppear {
            noteContent = NotesService.shared.getNote(for: repoPath)
            isSaved = true
        }
    }
}
