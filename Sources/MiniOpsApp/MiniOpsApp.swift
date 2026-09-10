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
                .frame(minWidth: 1000, minHeight: 680)
                .onAppear {
                    appDelegate.viewModel = sharedViewModel
                    for window in NSApp.windows where window.canBecomeKey {
                        window.delegate = appDelegate
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    sharedViewModel.isShowingSettingsSheet = true
                    NotificationCenter.default.post(name: .miniOpsOpenSettings, object: nil)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button("Open Workspace...") {
                    NotificationCenter.default.post(name: .miniOpsOpenWorkspace, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Clone Repository...") {
                    NotificationCenter.default.post(name: .miniOpsCloneRepo, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

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

                Button("Fetch") {
                    NotificationCenter.default.post(name: .miniOpsFetch, object: nil)
                }

                Button("Pull") {
                    NotificationCenter.default.post(name: .miniOpsPull, object: nil)
                }

                Button("Push") {
                    NotificationCenter.default.post(name: .miniOpsPush, object: nil)
                }

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
            let waitingCount = sharedViewModel.activeAgents.filter { $0.isWaitingForInput }.count
            let dirtyCount = sharedViewModel.repositories.filter { $0.isDirty }.count
            HStack(spacing: 3) {
                if waitingCount > 0 {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text("\(waitingCount)")
                } else {
                    Image(systemName: dirtyCount > 0 ? "circle.fill" : "checkmark.circle.fill")
                    if dirtyCount > 0 {
                        Text("\(dirtyCount)")
                    }
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: sharedViewModel)
        }
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
    static let miniOpsCloneRepo = Notification.Name("miniOpsCloneRepo")
    static let miniOpsOpenSettings = Notification.Name("miniOpsOpenSettings")
    static let miniOpsFetch = Notification.Name("miniOpsFetch")
    static let miniOpsPull = Notification.Name("miniOpsPull")
    static let miniOpsPush = Notification.Name("miniOpsPush")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var viewModel: WorkspaceViewModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        viewModel?.confirmLeavingEditor() == false ? .terminateCancel : .terminateNow
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        viewModel?.confirmLeavingEditor() ?? true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NotificationService.shared.requestAuthorization()

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.canBecomeKey && !NSStringFromClass(type(of: $0)).contains("StatusBar") }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        if !flag {
            for window in sender.windows where window.canBecomeKey && !NSStringFromClass(type(of: window)).contains("StatusBar") {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar even if window closed
        false
    }
}
