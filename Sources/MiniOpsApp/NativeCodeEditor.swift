import AppKit
import SwiftUI
import MiniOpsCore

public enum CodeSyntaxHighlighter {
    private static let keywords: Set<String> = [
        "import", "let", "var", "func", "class", "struct", "enum", "protocol", "extension",
        "public", "private", "fileprivate", "internal", "open", "static", "final", "mutating",
        "return", "if", "else", "guard", "switch", "case", "default", "for", "in", "while",
        "do", "try", "catch", "throw", "throws", "rethrows", "async", "await", "self", "Self",
        "init", "deinit", "subscript", "typealias", "associatedtype", "where", "break", "continue",
        "def", "from", "as", "with", "yield", "lambda", "elif", "except", "finally", "raise",
        "const", "function", "export", "interface", "type", "namespace", "declare",
        "package", "go", "select", "defer", "chan", "map", "range",
        "fn", "pub", "impl", "trait", "mod", "use", "match", "loop", "unsafe",
        "true", "false", "nil", "null", "None"
    ]

    public static func highlight(attributedString: NSMutableAttributedString, string: String) {
        let fullRange = NSRange(location: 0, length: string.utf16.count)
        guard fullRange.length > 0 else { return }

        // Default text color
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDark ? NSColor(calibratedRed: 0.9, green: 0.9, blue: 0.95, alpha: 1.0) : NSColor.textColor
        let keywordColor = isDark ? NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.65, alpha: 1.0) : NSColor(calibratedRed: 0.7, green: 0.1, blue: 0.4, alpha: 1.0)
        let stringColor = isDark ? NSColor(calibratedRed: 0.95, green: 0.8, blue: 0.5, alpha: 1.0) : NSColor(calibratedRed: 0.75, green: 0.35, blue: 0.1, alpha: 1.0)
        let commentColor = isDark ? NSColor(calibratedRed: 0.45, green: 0.55, blue: 0.6, alpha: 1.0) : NSColor(calibratedRed: 0.45, green: 0.5, blue: 0.55, alpha: 1.0)
        let numberColor = isDark ? NSColor(calibratedRed: 0.65, green: 0.85, blue: 0.95, alpha: 1.0) : NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.75, alpha: 1.0)

        attributedString.removeAttribute(.foregroundColor, range: fullRange)
        attributedString.addAttribute(.foregroundColor, value: textColor, range: fullRange)

        // Highlight strings: "..." and '...'
        if let stringRegex = try? NSRegularExpression(pattern: "\"(\\\\.|[^\"])*\"|'(\\\\.|[^'])*'", options: []) {
            for match in stringRegex.matches(in: string, options: [], range: fullRange) {
                attributedString.addAttribute(.foregroundColor, value: stringColor, range: match.range)
            }
        }

        // Highlight comments: //... and #...
        if let commentRegex = try? NSRegularExpression(pattern: "(//.*$)|(#.*$)", options: [.anchorsMatchLines]) {
            for match in commentRegex.matches(in: string, options: [], range: fullRange) {
                attributedString.addAttribute(.foregroundColor, value: commentColor, range: match.range)
            }
        }

        // Highlight numbers: \b\d+(\.\d+)?\b
        if let numRegex = try? NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b", options: []) {
            for match in numRegex.matches(in: string, options: [], range: fullRange) {
                attributedString.addAttribute(.foregroundColor, value: numberColor, range: match.range)
            }
        }

        // Highlight words/keywords
        if let wordRegex = try? NSRegularExpression(pattern: "\\b[a-zA-Z_][a-zA-Z0-9_]*\\b", options: []) {
            let nsString = string as NSString
            for match in wordRegex.matches(in: string, options: [], range: fullRange) {
                let word = nsString.substring(with: match.range)
                if keywords.contains(word) {
                    attributedString.addAttribute(.foregroundColor, value: keywordColor, range: match.range)
                }
            }
        }
    }
}

public class NativeTextView: NSTextView {
    public var onSave: (() -> Void)?

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f" {
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            performTextFinderAction(item)
            return true
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "s" {
            onSave?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

public struct NativeCodeEditorView: NSViewRepresentable {
    @Binding public var text: String
    @Binding public var isModified: Bool
    public var filePath: String
    public var onSave: () -> Void

    public init(text: Binding<String>, isModified: Binding<Bool>, filePath: String, onSave: @escaping () -> Void) {
        self._text = text
        self._isModified = isModified
        self.filePath = filePath
        self.onSave = onSave
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = false
        textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.addTextContainer(textContainer)

        let textView = NativeTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0.0, height: 0.0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        let font = TerminalSessionManager.shared.resolveNerdFont(size: 13)
        textView.font = font
        textView.delegate = context.coordinator
        textView.onSave = onSave

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.updateText(text, filePath: filePath)

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NativeTextView else { return }
        context.coordinator.parent = self
        textView.onSave = onSave
        if context.coordinator.currentFilePath != filePath || textView.string != text {
            context.coordinator.updateText(text, filePath: filePath)
        }
    }

    @MainActor public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeCodeEditorView
        weak var textView: NativeTextView?
        var currentFilePath: String = ""
        var isUpdatingInternally: Bool = false

        init(_ parent: NativeCodeEditorView) {
            self.parent = parent
        }

        func updateText(_ newText: String, filePath: String) {
            guard let textView = textView else { return }
            self.currentFilePath = filePath
            textView.undoManager?.removeAllActions()
            self.isUpdatingInternally = true

            let font = TerminalSessionManager.shared.resolveNerdFont(size: 13)
            let attr = NSMutableAttributedString(string: newText, attributes: [
                .font: font
            ])
            CodeSyntaxHighlighter.highlight(attributedString: attr, string: newText)
            textView.textStorage?.setAttributedString(attr)
            self.isUpdatingInternally = false
        }

        public func textDidChange(_ notification: Notification) {
            guard !isUpdatingInternally, let textView = textView else { return }
            let string = textView.string
            parent.text = string
            parent.isModified = true

            // Reapply highlighting without moving cursor
            let selectedRange = textView.selectedRange()
            isUpdatingInternally = true
            if let storage = textView.textStorage {
                let font = TerminalSessionManager.shared.resolveNerdFont(size: 13)
                storage.addAttribute(.font, value: font, range: NSRange(location: 0, length: string.utf16.count))
                CodeSyntaxHighlighter.highlight(attributedString: storage, string: string)
            }
            textView.setSelectedRange(selectedRange)
            isUpdatingInternally = false
        }
    }
}

public struct EditorContainerView: View {
    @Binding public var text: String
    @Binding public var isModified: Bool
    public var filePath: String
    public var onSave: () -> Void

    public init(text: Binding<String>, isModified: Binding<Bool>, filePath: String, onSave: @escaping () -> Void) {
        self._text = text
        self._isModified = isModified
        self.filePath = filePath
        self.onSave = onSave
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Editor Toolbar
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundColor(.secondary)
                Text(URL(fileURLWithPath: filePath).lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                if isModified {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .help("Unsaved changes")
                }
                Spacer()

                // Find button
                Button(action: {
                    let item = NSMenuItem()
                    item.tag = NSTextFinder.Action.showFindInterface.rawValue
                    NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: item)
                }) {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Search (Cmd+F)")

                // Save button
                Button(action: onSave) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save")
                    }
                    .font(.system(size: 11))
                }
                .disabled(!isModified)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Native Editor View
            NativeCodeEditorView(
                text: $text,
                isModified: $isModified,
                filePath: filePath,
                onSave: onSave
            )
        }
    }

}
