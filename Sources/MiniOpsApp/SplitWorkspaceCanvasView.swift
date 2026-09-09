import SwiftUI
import AppKit
import MiniOpsCore

public struct SplitWorkspaceCanvasView<EditorContent: View>: View {
    public let repoPath: String
    @Binding public var terminalRatio: Double
    @Binding public var isEditorCollapsed: Bool
    @Binding public var isTerminalCollapsed: Bool
    public let editorContent: () -> EditorContent
    public let onLayoutChange: () -> Void

    @State private var isDragging: Bool = false

    public init(
        repoPath: String,
        terminalRatio: Binding<Double>,
        isEditorCollapsed: Binding<Bool>,
        isTerminalCollapsed: Binding<Bool>,
        @ViewBuilder editorContent: @escaping () -> EditorContent,
        onLayoutChange: @escaping () -> Void
    ) {
        self.repoPath = repoPath
        self._terminalRatio = terminalRatio
        self._isEditorCollapsed = isEditorCollapsed
        self._isTerminalCollapsed = isTerminalCollapsed
        self.editorContent = editorContent
        self.onLayoutChange = onLayoutChange
    }

    public var body: some View {
        GeometryReader { geometry in
            let totalHeight = geometry.size.height
            let dividerHeight: CGFloat = 28

            if isEditorCollapsed && isTerminalCollapsed {
                // At least one must be visible
                Text("Both views collapsed")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isEditorCollapsed {
                // Terminal takes full height
                VStack(spacing: 0) {
                    terminalHeader(isFullScreen: true)
                    EmbeddedTerminalRepresentable(repoPath: repoPath)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if isTerminalCollapsed {
                // Editor takes full height
                VStack(spacing: 0) {
                    editorContent()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    terminalHeader(isFullScreen: false)
                }
            } else {
                // Split view with draggable divider
                let availableHeight = max(totalHeight - dividerHeight, 100)
                let termHeight = max(availableHeight * CGFloat(terminalRatio), 80)
                let editorHeight = max(availableHeight - termHeight, 80)

                VStack(spacing: 0) {
                    // Top: Editor
                    editorContent()
                        .frame(height: editorHeight)
                        .clipped()

                    // Middle: Draggable Divider Bar
                    dividerBar(totalHeight: availableHeight)
                        .frame(height: dividerHeight)

                    // Bottom: Terminal
                    EmbeddedTerminalRepresentable(repoPath: repoPath)
                        .frame(height: termHeight)
                        .clipped()
                }
            }
        }
    }

    private func dividerBar(totalHeight: CGFloat) -> some View {
        HStack(spacing: 12) {
            // Terminal Label & Status
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 11))
                Text("Terminal")
                    .font(.system(size: 11, weight: .semibold))
                Text("(/bin/zsh -l)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Drag handle visual indicator
            Capsule()
                .fill(isDragging ? Color.accentColor : Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)

            Spacer()

            // Collapse / Expand Controls
            HStack(spacing: 4) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditorCollapsed.toggle()
                        onLayoutChange()
                    }
                }) {
                    Image(systemName: isEditorCollapsed ? "arrow.down.forward.and.arrow.up.backward" : "chevron.up")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help(isEditorCollapsed ? "Restore Editor" : "Collapse Editor (Cmd+E)")

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTerminalCollapsed.toggle()
                        onLayoutChange()
                    }
                }) {
                    Image(systemName: isTerminalCollapsed ? "arrow.up.forward.and.arrow.down.backward" : "chevron.down")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help(isTerminalCollapsed ? "Restore Terminal" : "Collapse Terminal (Cmd+J)")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider(), alignment: .top)
        .overlay(Divider(), alignment: .bottom)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    isDragging = true
                    let delta = value.translation.height
                    let newHeight = (totalHeight * CGFloat(terminalRatio)) - delta
                    let newRatio = Double(newHeight / totalHeight)
                    terminalRatio = min(max(newRatio, 0.15), 0.85)
                }
                .onEnded { _ in
                    isDragging = false
                    onLayoutChange()
                }
        )
    }

    private func terminalHeader(isFullScreen: Bool) -> some View {
        HStack {
            Image(systemName: "terminal")
                .foregroundColor(.accentColor)
                .font(.system(size: 11))
            Text("Terminal")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isFullScreen {
                        isEditorCollapsed = false
                    } else {
                        isTerminalCollapsed = false
                    }
                    onLayoutChange()
                }
            }) {
                Text(isFullScreen ? "Restore Editor" : "Open Terminal")
                    .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }
}
