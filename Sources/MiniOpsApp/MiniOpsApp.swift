import SwiftUI
import AppKit
import MiniOpsCore

@main
struct MiniOpsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var sharedViewModel = WorkspaceViewModel()

    var body: some Scene {
        WindowGroup {
            MainWindowView(viewModel: sharedViewModel)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .newItem) {
                Button("Open Workspace...") {
                    NotificationCenter.default.post(name: .miniOpsOpenWorkspace, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Save File") {
                    NotificationCenter.default.post(name: .miniOpsSaveFile, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            CommandMenu("Git") {
                Button("Commit Changes...") {
                    NotificationCenter.default.post(name: .miniOpsToggleGitInspector, object: nil)
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("Reconcile Latest Changes") {
                    NotificationCenter.default.post(name: .miniOpsReconcile, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Refresh Git Status") {
                    NotificationCenter.default.post(name: .miniOpsRefreshGitStatus, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            CommandMenu("Terminal") {
                Button("Toggle Terminal") {
                    NotificationCenter.default.post(name: .miniOpsToggleTerminal, object: nil)
                }
                .keyboardShortcut("j", modifiers: .command)

                Button("Toggle Editor") {
                    NotificationCenter.default.post(name: .miniOpsToggleEditor, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarExtraView(viewModel: sharedViewModel)
        } label: {
            let dirtyCount = sharedViewModel.repositories.filter { $0.isDirty }.count
            HStack(spacing: 3) {
                Image(systemName: dirtyCount > 0 ? "circle.fill" : "checkmark.circle.fill")
                if dirtyCount > 0 {
                    Text("\(dirtyCount)")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

extension Notification.Name {
    static let miniOpsOpenWorkspace = Notification.Name("miniOpsOpenWorkspace")
    static let miniOpsSaveFile = Notification.Name("miniOpsSaveFile")
    static let miniOpsToggleGitInspector = Notification.Name("miniOpsToggleGitInspector")
    static let miniOpsReconcile = Notification.Name("miniOpsReconcile")
    static let miniOpsRefreshGitStatus = Notification.Name("miniOpsRefreshGitStatus")
    static let miniOpsToggleTerminal = Notification.Name("miniOpsToggleTerminal")
    static let miniOpsToggleEditor = Notification.Name("miniOpsToggleEditor")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NotificationService.shared.requestAuthorization()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar even if window closed
        false
    }
}
